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
      pending_relationships = Bulkrax::PendingRelationship.find_each.select do |rel|
        rel.bulkrax_importer_run_id == importer_run_id && rel.parent_id == parent_identifier
      end.sort_by(&:order)

      @importer_run_id = importer_run_id
      @parent_entry, @parent_record = find_record(parent_identifier, importer_run_id)
      @child_records = { works: [], collections: [] }
      pending_relationships.each do |rel|
        raise ::StandardError, %("#{rel}" needs either a child or a parent to create a relationship) if rel.child_id.nil? || rel.parent_id.nil?
        @child_entry, child_record = find_record(rel.child_id, importer_run_id)
        child_record.is_a?(::Collection) ? @child_records[:collections] << child_record : @child_records[:works] << child_record
      end

      if (child_records[:collections].blank? && child_records[:works].blank?) || parent_record.blank?
        reschedule(
          parent_identifier: parent_identifier,
          importer_run_id: importer_run_id
        )
        return false # stop current job from continuing to run after rescheduling
      end 

      @parent_entry ||= Bulkrax::Entry.where(identifier: parent_identifier,
                                             importerexporter_id: ImporterRun.find(importer_run_id).importer_id,
                                             importerexporter_type: "Bulkrax::Importer").first
      create_relationships
      pending_relationships.each(&:destroy)
    rescue ::StandardError => e
      parent_entry ? parent_entry.status_info(e) : child_entry.status_info(e)
      Bulkrax::ImporterRun.find(importer_run_id).increment!(:failed_relationships) # rubocop:disable Rails/SkipsModelValidations
    end

    private

    def create_relationships
      if parent_record.is_a?(::Collection)
        collection_parent_work_child unless child_records[:works].empty?
        collection_parent_collection_child unless child_records[:collections].empty?
      else
        work_parent_work_child unless child_records[:works].empty?
        raise ::StandardError, 'a Collection may not be assigned as a child of a Work' if child_records[:collections].present?
      end
    end

    def user
      @user ||= Bulkrax::ImporterRun.find(importer_run_id).importer.user
    end

    # Work-Collection membership is added to the child as member_of_collection_ids
    # This is adding the reverse relationship, from the child to the parent
    def collection_parent_work_child
      child_records[:works].each do |child_record|
        ::Hyrax::Collections::NestedCollectionPersistenceService.persist_nested_collection_for(parent: parent_record, child: child_record)
        # TODO: add counters for :processed_parents and :failed_parents
        Bulkrax::ImporterRun.find(importer_run_id).increment!(:processed_relationships) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    # Collection-Collection membership is added to the as member_ids
    def collection_parent_collection_child
      child_records[:collections].each do |child_record|
        ::Hyrax::Collections::NestedCollectionPersistenceService.persist_nested_collection_for(parent: parent_record, child: child_record)
        Bulkrax::ImporterRun.find(importer_run_id).increment!(:processed_relationships) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    # Work-Work membership is added to the parent as member_ids
    def work_parent_work_child
      records_hash = {}
      child_records[:works].each_with_index do |child_record, i|
        records_hash[i] = { id: child_record.id }
      end
      attrs = {
        work_members_attributes: records_hash
      }
      parent_record.reindex_extent = Hyrax::Adapters::NestingIndexAdapter::LIMITED_REINDEX if parent_record.respond_to?(:reindex_extent)
      env = Hyrax::Actors::Environment.new(parent_record, Ability.new(user), attrs)
      Hyrax::CurationConcern.actor.update(env)
      # TODO: add counters for :processed_parents and :failed_parents
      Bulkrax::ImporterRun.find(importer_run_id).increment!(:processed_relationships) # rubocop:disable Rails/SkipsModelValidations
    end

    def reschedule(parent_identifier:, importer_run_id:)
      CreateRelationshipsJob.set(wait: 10.minutes).perform_later(
        parent_identifier: parent_identifier,
        importer_run_id: importer_run_id
      )
    end
  end
end
