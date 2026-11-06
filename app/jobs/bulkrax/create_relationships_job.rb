# frozen_string_literal: true

module Bulkrax
  ##
  # Responsible for creating parent-child relationships between Works and Collections.
  #
  # Handles three kinds of relationships:
  # - Work to Collection
  # - Collection to Collection
  # - Work to Work
  #
  # These can be established from either side of the relationship (i.e. from parent to child or from child to parent).
  # This job only creates one relationship at a time. If a record needs multiple parents or children or both, individual
  # jobs should be run for each of those relationships.
  #
  # NOTE: In the context of this job, "record" is used to generically refer
  #       to either an instance of a Work or an instance of a Collection.
  # NOTE: In the context of this job, "identifier" is used to generically refer
  #       to either a record's ID or an Bulkrax::Entry's source_identifier.
  # Please override with your own job for custom/non-hyrax applications
  # set Bulkrax config variable :relationship_job to your custom class
  class CreateRelationshipsJob < ApplicationJob # rubocop:disable Metrics/ClassLength
    ##
    # @api public
    # @since v5.0.1
    #
    # Once we've created the relationships, should we then index the works's file_sets to ensure
    # that we have the proper indexed values.  This can help set things like `is_page_of_ssim` for
    # IIIF manifest and search results of file sets.
    #
    # @note As of v5.0.1 the default behavior is to not perform this.  That preserves past
    #       implementations.  However, we might determine that we want to change the default
    #       behavior.  Which would likely mean a major version change.
    #
    # @example
    #   # In config/initializers/bulkrax.rb
    #   Bulkrax::CreateRelationshipsJob.update_child_records_works_file_sets = true
    #
    # @see https://github.com/scientist-softserv/louisville-hyku/commit/128a9ef
    class_attribute :update_child_records_works_file_sets, default: false
    class_attribute :max_failure_count, default: 5
    # The size of bulkrax_pending_relationships.status_message on databases
    # that enforce string limits, such as MySQL.
    STATUS_MESSAGE_LIMIT = 255

    include DynamicRecordLookup

    queue_as Bulkrax.config.ingest_queue_name

    attr_accessor :user, :importer_run, :errors, :importer_run_id, :ability, :number_of_successes, :number_of_failures
    ##
    # @param parent_identifier [String] Work/Collection ID or Bulkrax::Entry source_identifiers
    # @param importer_run [Bulkrax::ImporterRun] current importer run (needed to properly update counters)
    #
    # The entry_identifier is used to lookup the @base_entry for the job (a.k.a. the entry the job was called from).
    # The @base_entry defines the context of the relationship (e.g. "this entry (@base_entry) should have a parent").
    # Whether the @base_entry is the parent or the child in the relationship is determined by the presence of a
    # parent_identifier or child_identifier param. For example, if a parent_identifier is passed, we know @base_entry
    # is the child in the relationship, and vice versa if a child_identifier is passed.
    #
    # rubocop:disable Metrics/MethodLength
    def perform(parent_identifier:, importer_run_id: nil, run_user: nil, failure_count: 0) # rubocop:disable Metrics/AbcSize
      @importer_run_id = importer_run_id
      @importer_run = Bulkrax::ImporterRun.find(@importer_run_id) if @importer_run_id
      @user = run_user || importer_run&.user
      @ability = Ability.new(@user)

      @number_of_successes = 0
      @number_of_failures = 0
      @errors = []
      @parent_record_members_added = false
      @last_attempt = failure_count + 1 >= max_failure_count

      parent_entry, parent_record = find_record(parent_identifier, @importer_run_id)
      if parent_record
        # Works and collections are different breeds of animals:
        # - works know both their children (file_sets and child works) in member_ids
        # - works and collections know their parents (collections) in member_of_collection_ids
        # We need to handle the two differently by locking the records appropriately to avoid race condition errors.
        if parent_record.is_a?(Bulkrax.collection_model_class)
          process_parent_as_collection(parent_record: parent_record, parent_identifier: parent_identifier)
        else
          process_parent_as_work(parent_record: parent_record, parent_identifier: parent_identifier)
        end
      else
        @number_of_failures = 1
        @errors = ["Parent record #{parent_identifier} not yet available for creating relationships with children records."]
      end

      # Counted on a failed pass too: a linked relationship is destroyed, so no retry counts it
      # rubocop:disable Rails/SkipsModelValidations
      ImporterRun.update_counters(@importer_run_id, processed_relationships: @number_of_successes) if @number_of_successes.positive?
      # rubocop:enable Rails/SkipsModelValidations
      record_relationship_failures if @permanent_failures
      if @errors.present?
        parent_entry&.set_status_info(@errors.last, importer_run)
        failure_count += 1

        if failure_count < max_failure_count
          reschedule(
            parent_identifier: parent_identifier,
            importer_run_id: @importer_run_id,
            run_user: @user,
            failure_count: failure_count
          )
          recount_if_failures_counted
        else
          fail_relationships(parent_identifier)
        end
        return @errors # stop current job from continuing to run after rescheduling
      else
        recount_if_failures_counted
      end
    end
    # rubocop:enable Metrics/MethodLength

    private

    ##
    # We can use Hyrax's lock manager when we have one available.
    # However it's not certain that this is actually working, so to be
    # as safe as possible, we will reload resources before we update.
    if Bulkrax.hyrax_loaded?
      include Hyrax::Lockable

      def conditionally_acquire_lock_for(*args, &block)
        if Bulkrax.use_locking?
          acquire_lock_for(*args, &block)
        else
          yield
        end
      end
    else
      # Otherwise, we're providing no meaningful lock manager at this time.
      def acquire_lock_for(*)
        yield
      end

      alias conditionally_acquire_lock_for acquire_lock_for
    end

    # When the parent is a collection, we save the relationship on each child.
    # The parent does not need to be saved, as the relationship is stored on the child.
    # but we do reindex the parent after all the children are added.
    # rubocop:disable Layout/RescueEnsureAlignment
    def process_parent_as_collection(parent_record:, parent_identifier:)
      ActiveRecord::Base.uncached do
        Bulkrax::PendingRelationship.where(parent_id: parent_identifier, importer_run_id: @importer_run_id)
                                    .ordered.find_each do |rel|
          raise "#{rel} needs a child to create relationship" if rel.child_id.nil?
          raise "#{rel} needs a parent to create relationship" if rel.parent_id.nil?
          add_to_collection(relationship: rel, parent_record: parent_record, ability: ability)
          @number_of_successes += 1
          @parent_record_members_added = true
        rescue => e
          rel.update(status_message: e.message.truncate(STATUS_MESSAGE_LIMIT)) if @last_attempt
          @number_of_failures += 1
          @errors << e
        end
      end
      # if collection members were added, we reindex the collection
      # The collection members have already saved the relationships
      # To index the parent, we want to make sure we have the latest version of the parent,
      # because another job may have updated it in the meantime.
      return unless @parent_record_members_added
      reloaded_parent = Bulkrax.object_factory.find(parent_record.id)
      Bulkrax.object_factory.update_index(resources: [reloaded_parent])
      Bulkrax.object_factory.publish(event: 'object.membership.updated', object: reloaded_parent, user: @user)
    end
    # rubocop:enable Layout/RescueEnsureAlignment

    # When the parent is a work, we save the relationship on the parent.
    # We prefer to save all of the member relationships and then save the parent once. Concurrent
    # jobs may be trying to save the parent at the same time, so we need to lock the parent
    # record while we are adding the children to it.
    # However the locking appears to not be working so as a workaround we will save each member as we go,
    # but only index the parent once at the end.
    # rubocop:disable Layout/RescueEnsureAlignment
    def process_parent_as_work(parent_record:, parent_identifier:)
      conditionally_acquire_lock_for(parent_record.id.to_s) do
        ActiveRecord::Base.uncached do
          # find_each would ignore the order; id breaks ties among children named in one cell
          Bulkrax::PendingRelationship.where(parent_id: parent_identifier, importer_run_id: @importer_run_id)
                                      .ordered.order(:id).each do |rel|
            raise "#{rel} needs a child to create relationship" if rel.child_id.nil?
            raise "#{rel} needs a parent to create relationship" if rel.parent_id.nil?
            # depending on the object factory, we may not save the actual parent record, so we update it here
            # after each relationship to ensure that we don't lose the membership.
            parent_record = add_to_work(relationship: rel, parent_record: parent_record, ability: ability)
            @parent_record_members_added = true
          rescue FileSetInAnotherWorkError => e
            fail_for_good(rel, e)
          rescue => e
            rel.update(status_message: e.message.truncate(STATUS_MESSAGE_LIMIT)) if @last_attempt
            @number_of_failures += 1
            @errors << e
          end
        end

        # save record if members were added and update the index.
        # For valkyrie, we should only need to reindex, but for active fedora, both the save
        # and the reindex are needed to ensure the relationships are properly persisted.
        if @parent_record_members_added
          Bulkrax.object_factory.save!(resource: parent_record, user: @user)
          reloaded_parent = Bulkrax.object_factory.find(parent_record.id)
          Bulkrax.object_factory.update_index(resources: [reloaded_parent])
          Bulkrax.object_factory.publish(event: 'object.membership.updated', object: reloaded_parent, user: @user)
        end
        # Only once the work is saved: if that fails, the relationships stay for the retry.
        # Under the lock, so another pass for the work cannot finish the same ones.
        finish_linked_relationships
      end
    rescue => e
      # Recorded rather than raised, so #perform reschedules the pass whatever the queue adapter's retry policy
      record_pass_failure(parent_identifier, e)
    end
    # rubocop:enable Layout/RescueEnsureAlignment

    # NOTE: the child changes are saved in the object factory.
    def add_to_collection(relationship:, parent_record:, ability:)
      ActiveRecord::Base.uncached do
        _child_entry, child_record = find_record(relationship.child_id, @importer_run_id)
        raise child_not_found(relationship) unless child_record
        raise "Cannot add child collection (ID=#{relationship.child_id}) to parent work (ID=#{relationship.parent_id})" if child_record.collection? && parent_record.work?
        ability.authorize!(:edit, child_record)
        # We could do this outside of the loop, but that could lead to odd counter failures.
        ability.authorize!(:edit, parent_record)
        # It is important to lock the child records as they are the ones being saved.
        # However, locking doesn't seem to be working so we will reload the child record before saving.
        # This is a workaround for the fact that the lock manager doesn't seem to be working.
        conditionally_acquire_lock_for(child_record.id.to_s) do
          Bulkrax.object_factory.add_resource_to_collection(
            collection: parent_record,
            resource: child_record,
            user: @user
          )
        end
        relationship.destroy
      end
    end

    # NOTE: we only update the parent's member_ids and prefer to not save the parent until all children are added.
    # However, the locking appears to be working so as a workaround we will save each member as we go.
    # This is a workaround for the fact that the lock manager doesn't seem to be working.
    # To avoid having to reload the parent, we return the updated parent to the calling method.
    def add_to_work(relationship:, parent_record:, ability:)
      _child_entry, child_record = find_record(relationship.child_id, @importer_run_id)
      raise child_not_found(relationship) unless child_record
      raise "Cannot add child collection (ID=#{relationship.child_id}) to parent work (ID=#{relationship.parent_id})" if child_record.collection? && parent_record.work?

      ability.authorize!(:edit, child_record)
      # We could do this outside of the loop, but that could lead to odd counter failures.
      ability.authorize!(:edit, parent_record)
      updated_parent = Bulkrax.object_factory.add_child_to_parent_work(
        parent: parent_record,
        child: child_record
      )
      Bulkrax.object_factory.inherit_parent_visibility(parent: updated_parent, resource: child_record) if relationship.inherit_parent_visibility?
      # default is false for this... do not typically need to index file sets of child records
      Bulkrax.object_factory.update_index_for_file_sets_of(resource: child_record) if update_child_records_works_file_sets?
      linked_relationships << [relationship, Bulkrax.object_factory.uploads_awaiting_ingest(resource: child_record)]

      updated_parent
    end

    def linked_relationships
      @linked_relationships ||= []
    end

    # No retry can change the answer, so it fails now rather than after max_failure_count passes
    def fail_for_good(relationship, error)
      relationship.update(status_message: error.message.truncate(STATUS_MESSAGE_LIMIT))
      @number_of_failures += 1
      @permanent_failures = true
    end

    def record_pass_failure(parent_identifier, error)
      @number_of_failures += 1
      @errors << error
      # No longer Pending, so a stalled ScheduleRelationshipsJob leaves them to this job's
      # reschedule rather than retrying them hourly, which looks like progress and never gives up
      relationships = Bulkrax::PendingRelationship.where(parent_id: parent_identifier, importer_run_id: @importer_run_id)
      relationships.pending.update_all(status_message: error.message.truncate(STATUS_MESSAGE_LIMIT)) # rubocop:disable Rails/SkipsModelValidations
      # Counted, so the pass that links them recounts and sets the importer's status back
      record_relationship_failures
    end

    # Ingest runs with the file set in its saved work, never mid-pass
    def finish_linked_relationships
      queued = Set.new
      linked_relationships.each do |relationship, uploads|
        uploads.each { |upload| Bulkrax.object_factory.ingest_later(upload: upload) if queued.add?(upload.id) }
        relationship.destroy
        self.number_of_successes += 1
      end
    end

    def child_not_found(relationship)
      "Child record #{relationship.child_id} could not be found for parent #{relationship.parent_id}"
    end

    # Only the last attempt records errors on relationships, so a relationship
    # that is no longer Pending failed for good and one that links on a retry
    # is never reported. A missing parent leaves its relationships untried, so
    # they get the parent's error here.
    def fail_relationships(parent_identifier)
      relationships = Bulkrax::PendingRelationship.where(parent_id: parent_identifier, importer_run_id: @importer_run_id)
      # rubocop:disable Rails/SkipsModelValidations
      relationships.pending.update_all(status_message: @errors.last.to_s.truncate(STATUS_MESSAGE_LIMIT))
      # rubocop:enable Rails/SkipsModelValidations
      record_relationship_failures
    end

    # Counts failed relationships from their rows rather than adding to the
    # counter, because a later run of this job may fail or link the same ones.
    # The run's row stays locked through the importer status, as it does in the
    # import jobs, so jobs finishing together count and record in turn.
    def record_relationship_failures
      return unless @importer_run_id

      ImporterRun.transaction do
        failed = ImporterRun.lock.find(@importer_run_id).pending_relationships.where.not(status_message: 'Pending').count
        # rubocop:disable Rails/SkipsModelValidations
        ImporterRun.where(id: @importer_run_id).update_all(failed_relationships: failed)
        # rubocop:enable Rails/SkipsModelValidations
        record_importer_status
      end
    end

    # Linking a relationship that any run of this job failed must clear it,
    # even when this attempt loaded it while it was still Pending. The counter
    # is read under the run's lock, so a run of this job that is recording a
    # failure finishes first.
    def recount_if_failures_counted
      return unless @importer_run_id && @number_of_successes.positive?

      ImporterRun.transaction do
        record_relationship_failures if ImporterRun.lock.find(@importer_run_id).failed_relationships.to_i.positive?
      end
    end

    # A chain from an earlier run must not set the status of a newer one.
    def record_importer_status
      importer = importer_run&.importer
      return unless importer && importer.last_run == importer_run

      importer.current_run = importer_run
      importer.record_status
    end

    def reschedule(**kargs)
      CreateRelationshipsJob.set(wait: 10.minutes).perform_later(**kargs)
    end
  end
end
