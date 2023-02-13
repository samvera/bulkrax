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

    attr_accessor :child_records, :child_entry, :parent_record, :parent_entry, :importer_run_id

    # @param parent_identifier [String] Work/Collection ID or Bulkrax::Entry source_identifiers
    # @param importer_run [Bulkrax::ImporterRun] current importer run (needed to properly update counters)
    #
    # The entry_identifier is used to lookup the @base_entry for the job (a.k.a. the entry the job was called from).
    # The @base_entry defines the context of the relationship (e.g. "this entry (@base_entry) should have a parent").
    # Whether the @base_entry is the parent or the child in the relationship is determined by the presence of a
    # parent_identifier or child_identifier param. For example, if a parent_identifier is passed, we know @base_entry
    # is the child in the relationship, and vice versa if a child_identifier is passed.
    def perform(parent_identifier:, importer_run_id:) # rubocop:disable Metrics/AbcSize
      # TODO permission checks on child / parent write access

      # TODO rename order field literally anything else. use it for sort
      pending_relationships = Bulkrax::PendingRelationship.where(parent_id: parent_identifier, importer_run_id: importer_run_id).order('created_at')

      parent_entry, parent_record = find_record(parent_identifier, importer_run_id)
      errors = []
      pending_relationships.find_each do |rel|
        begin
          errors << "#{rel} needs a child to create relationship" if rel.child_id.nil?
          errors << "#{rel} needs a parent to create relationship" if rel.parent_id.nil?
          next if rel.child_id.nil? || rel.parent_id.nil?

          _child_entry, child_record = find_record(rel.child_id, importer_run_id)
          errors << "#{rel} could not find child" unless child_record
          parent_record.is_a?(Collection) ? add_to_collection(child_record, parent_record) : add_to_work(child_record, parent_record)
          child_record.save!
          child_record.file_sets.each(&:update_index) if update_child_records_works_file_sets?
          # TODO update counters
          rel.destroy
        rescue => e
          errors << "#{rel} failed because of #{e.message}\n#{e.backtrace}"
        end
      end
      # save record if members were added
      parent_record.save!

      if errors.present?
        reschedule({ parent_identifier: parent_identifier, importer_run_id: importer_run_id })
        return false # stop current job from continuing to run after rescheduling
      end
   end

    private

    def add_to_collection(child_record, parent_record)
      child_record.member_of_collections << parent_record
      child_record.save!
    end

    def add_to_work(child_record, parent_record)
      parent_record.ordered_members << child_record unless parent_record.includes?(child_record)
    end

    def reschedule(parent_identifier:, importer_run_id:)
      CreateRelationshipsJob.set(wait: 10.minutes).perform_later(
        parent_identifier: parent_identifier,
        importer_run_id: importer_run_id
      )
    end
  end
end
