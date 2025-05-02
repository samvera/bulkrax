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
  class CreateRelationshipsJob < ApplicationJob
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
      @importer_run = Bulkrax::ImporterRun.find(importer_run_id) if importer_run_id
      @user = run_user || importer_run&.user
      @ability = Ability.new(@user)

      @number_of_successes = 0
      @number_of_failures = 0
      @errors = []
      @parent_record_members_added = false

      parent_entry, parent_record = find_record(parent_identifier, importer_run_id)
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

      if @errors.present?
        # rubocop:disable Rails/SkipsModelValidations
        ImporterRun.update_counters(importer_run_id, failed_relationships: @number_of_failures)
        # rubocop:enable Rails/SkipsModelValidations

        parent_entry&.set_status_info(@errors.last, importer_run)
        failure_count += 1

        if failure_count < max_failure_count
          reschedule(
            parent_identifier: parent_identifier,
            importer_run_id: importer_run_id,
            run_user: @user,
            failure_count: failure_count
          )
        end
        return @errors # stop current job from continuing to run after rescheduling
      else
        # rubocop:disable Rails/SkipsModelValidations
        ImporterRun.update_counters(importer_run_id, processed_relationships: @number_of_successes)
        # rubocop:enable Rails/SkipsModelValidations
      end
    end
    # rubocop:enable Metrics/MethodLength

    private

    ##
    # We can use Hyrax's lock manager when we have one available.
    if defined?(::Hyrax)
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
    def process_parent_as_collection(parent_record:, parent_identifier:)
      ActiveRecord::Base.uncached do
        Bulkrax::PendingRelationship.where(parent_id: parent_identifier)
                                    .ordered.find_each do |rel|
          raise "#{rel} needs a child to create relationship" if rel.child_id.nil?
          raise "#{rel} needs a parent to create relationship" if rel.parent_id.nil?
          add_to_collection(relationship: rel, parent_record: parent_record, ability: ability)
          @number_of_successes += 1
          @parent_record_members_added = true
        rescue => e
          rel.update(status_message: e.message)
          @number_of_failures += 1
          @errors << e
        end
      end

      # if collection members were added, we reindex the collection
      # The collection members have already saved the relationships
      return unless @parent_record_members_added
      Bulkrax.object_factory.update_index(resources: [parent_record])
      Bulkrax.object_factory.publish(event: 'object.membership.updated', object: parent_record, user: @user)
    end

    # When the parent is a work, we save the relationship on the parent.
    # We save all of the children and then save the parent once.
    def process_parent_as_work(parent_record:, parent_identifier:)
      conditionally_acquire_lock_for(parent_record.id.to_s) do
        ActiveRecord::Base.uncached do
          Bulkrax::PendingRelationship.where(parent_id: parent_identifier)
                                      .ordered.find_each do |rel|
            raise "#{rel} needs a child to create relationship" if rel.child_id.nil?
            raise "#{rel} needs a parent to create relationship" if rel.parent_id.nil?
            add_to_work(relationship: rel, parent_record: parent_record, ability: ability)
            self.number_of_successes += 1
            @parent_record_members_added = true
          rescue => e
            rel.update(status_message: e.message)
            @number_of_failures += 1
            @errors << e
          end
        end

        # save record if members were added
        if @parent_record_members_added
          Bulkrax.object_factory.save!(resource: parent_record, user: @user)
          Bulkrax.object_factory.publish(event: 'object.membership.updated', object: parent_record, user: @user)
        end
      end
    end

    # NOTE: This should not persist changes to the
    # child nor parent.  We'll do that elsewhere in this loop.
    # It is important to lock the child records as they are the ones being saved.
    def add_to_collection(relationship:, parent_record:, ability:)
      _child_entry, child_record = find_record(relationship.child_id, importer_run_id)
      conditionally_acquire_lock_for(child_record.id.to_s) do
        raise "#{relationship} could not find child record" unless child_record
        raise "Cannot add child collection (ID=#{relationship.child_id}) to parent work (ID=#{relationship.parent_id})" if child_record.collection? && parent_record.work?
        ability.authorize!(:edit, child_record)
        # We could do this outside of the loop, but that could lead to odd counter failures.
        ability.authorize!(:edit, parent_record)
        Bulkrax.object_factory.add_resource_to_collection(
          collection: parent_record,
          resource: child_record,
          user: @user
        )
      end
      relationship.destroy
    end

    # NOTE: This should not persist changes to the
    # child nor parent.  We'll do that elsewhere in this loop.
    def add_to_work(relationship:, parent_record:, ability:)
      _child_entry, child_record = find_record(relationship.child_id, importer_run_id)
      raise "#{relationship} could not find child record" unless child_record
      raise "Cannot add child collection (ID=#{relationship.child_id}) to parent work (ID=#{relationship.parent_id})" if child_record.collection? && parent_record.work?

      ability.authorize!(:edit, child_record)
      # We could do this outside of the loop, but that could lead to odd counter failures.
      ability.authorize!(:edit, parent_record)

      Bulkrax.object_factory.add_child_to_parent_work(
        parent: parent_record,
        child: child_record
      )
      # default is false for this... do not typically need to index file sets of child records
      Bulkrax.object_factory.update_index_for_file_sets_of(resource: child_record) if update_child_records_works_file_sets?
      relationship.destroy
    end

    def reschedule(**kargs)
      CreateRelationshipsJob.set(wait: 10.minutes).perform_later(**kargs)
    end
  end
end
