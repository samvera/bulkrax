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

      ActiveRecord::Base.uncached do
        Bulkrax::PendingRelationship.where(parent_id: parent_identifier, importer_run_id: importer_run_id)
                                    .ordered.find_each do |rel|
          process(relationship: rel, importer_run_id: importer_run_id, parent_record: parent_record, ability: ability)
          number_of_successes += 1
          Rails.logger.error("Success: #{number_of_successes} - Object Count #{ObjectSpace.each_object(Object).count}")
        rescue => e
          number_of_failures += 1
          errors << e
          Rails.logger.error("Failure: #{number_of_failures} - #{e.message} - #{errors.size} - #{ObjectSpace.each_object(Object).count}")
        end
      end

      # save record if members were added
      parent_record.save! if @parent_record_members_added

      # rubocop:disable Rails/SkipsModelValidations
      if errors.present?
        importer_run.increment!(:failed_relationships, number_of_failures)
        parent_entry&.set_status_info(errors.last, importer_run)

        # TODO: This can create an infinite job cycle, consider a time to live tracker.
        reschedule({ parent_identifier: parent_identifier, importer_run_id: importer_run_id })
        return false # stop current job from continuing to run after rescheduling
      else
        Bulkrax::ImporterRun.find(importer_run_id).increment!(:processed_relationships, number_of_successes)
      end
      # rubocop:enable Rails/SkipsModelValidations
    end
    # rubocop:enable Metrics/MethodLength

    private

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
      child_record.member_of_collections << parent_record
      child_record.save!
    end

    def add_to_work(child_record, parent_record)
      return true if parent_record.ordered_members.to_a.include?(child_record)

      parent_record.ordered_members << child_record
      @parent_record_members_added = true
      # TODO: Do we need to save the child record?
      child_record.save!
    end

    def reschedule(parent_identifier:, importer_run_id:)
      CreateRelationshipsJob.set(wait: 10.minutes).perform_later(
        parent_identifier: parent_identifier,
        importer_run_id: importer_run_id
      )
    end
  end
end
