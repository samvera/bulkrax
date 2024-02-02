# frozen_string_literal: true

module Bulkrax
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

    include DynamicRecordLookup

    queue_as :import

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
    def perform(parent_identifier:, importer_run_id:) # rubocop:disable Metrics/AbcSize
      importer_run = Bulkrax::ImporterRun.find(importer_run_id)
      ability = Ability.new(importer_run.user)

      parent_entry, parent_record = find_record(parent_identifier, importer_run_id)

      number_of_successes = 0
      number_of_failures = 0
      errors = []
      @parent_record_members_added = false
      @child_members_added = []

      if parent_record
        conditionally_acquire_lock_for(parent_record.id) do
          ActiveRecord::Base.uncached do
            Bulkrax::PendingRelationship.where(parent_id: parent_identifier, importer_run_id: importer_run_id)
                                        .ordered.find_each do |rel|
              process(relationship: rel, importer_run_id: importer_run_id, parent_record: parent_record, ability: ability)
              number_of_successes += 1
            rescue => e
              number_of_failures += 1
              errors << e
            end
          end

          # save record if members were added
          if @parent_record_members_added
            parent_record.save!
            # Ensure that the new relationship gets indexed onto the children
            if parent_record.kind_of?(Valkyrie::Resource)
              @child_members_added.each do |child|
                Hyrax.index_adapter.save(resource: child)
              end
            else
              @child_members_added.each(&:update_index)
            end
          end
        end
      else
        # In moving the check of the parent record "up" we've exposed a hidden reporting foible.
        # Namely we were reporting one error per child record when the parent record was itself
        # unavailable.
        #
        # We have chosen not to duplicate that "number of errors" as it does not seem like the
        # correct pattern for reporting a singular error (the previous pattern being one error per
        # child who's parent is not yet created).
        number_of_failures = 1
        errors = ["Parent record not yet available for creating relationships with children records."]
      end

      if errors.present?
        # rubocop:disable Rails/SkipsModelValidations
        ImporterRun.update_counters(importer_run_id, failed_relationships: number_of_failures)
        # rubocop:enable Rails/SkipsModelValidations

        parent_entry&.set_status_info(errors.last, importer_run)

        # TODO: This can create an infinite job cycle, consider a time to live tracker.
        reschedule({ parent_identifier: parent_identifier, importer_run_id: importer_run_id })
        return false # stop current job from continuing to run after rescheduling
      else
        # rubocop:disable Rails/SkipsModelValidations
        ImporterRun.update_counters(importer_run_id, processed_relationships: number_of_successes)
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

    def process(relationship:, importer_run_id:, parent_record:, ability:)
      raise "#{relationship} needs a child to create relationship" if relationship.child_id.nil?
      raise "#{relationship} needs a parent to create relationship" if relationship.parent_id.nil?

      _child_entry, child_record = find_record(relationship.child_id, importer_run_id)
      raise "#{relationship} could not find child record" unless child_record

      raise "Cannot add child collection (ID=#{relationship.child_id}) to parent work (ID=#{relationship.parent_id})" if child_record.collection? && parent_record.work?

      ability.authorize!(:edit, child_record)

      # We could do this outside of the loop, but that could lead to odd counter failures.
      ability.authorize!(:edit, parent_record)

      parent_record.is_a?(Collection) ? add_to_collection(child_record, parent_record) : add_to_work(child_record, parent_record)

      child_record.file_sets.each(&:update_index) if update_child_records_works_file_sets? && child_record.respond_to?(:file_sets)
      relationship.destroy
    end

    def add_to_collection(child_record, parent_record)
      parent_record.try(:reindex_extent=, Hyrax::Adapters::NestingIndexAdapter::LIMITED_REINDEX) if
        defined?(Hyrax::Adapters::NestingIndexAdapter)
      child_record.member_of_collections << parent_record
      child_record.save!
    end

    def add_to_work(child_record, parent_record)
      parent_record.kind_of?(Valkyrie::Resource) ? add_to_valkyrie_work(child_record, parent_record) : add_to_af_work(child_record, parent_record)

      @parent_record_members_added = true
      @child_members_added << child_record
    end

    def add_to_valkyrie_work(child_record, parent_record)
      return true if parent_record.member_ids.include?(child_record.id)

      parent_record.member_ids << child_record.id
      change_set = Hyrax::ChangeSet.for(parent_record)
      Hyrax::Transactions::Container['change_set.update_work'].call(change_set)
    end

    def add_to_af_work(child_record, parent_record)
      return true if parent_record.ordered_members.to_a.include?(child_record)

      parent_record.ordered_members << child_record
    end

    def reschedule(parent_identifier:, importer_run_id:)
      CreateRelationshipsJob.set(wait: 10.minutes).perform_later(
        parent_identifier: parent_identifier,
        importer_run_id: importer_run_id
      )
    end
  end
end
