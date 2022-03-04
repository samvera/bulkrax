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

    attr_accessor :child_records, :parent_record, :parent_entry, :importer_run_id

    # @param parent_identifier [String] Work/Collection ID or Bulkrax::Entry source_identifiers
    # @param importer_run [Bulkrax::ImporterRun] current importer run (needed to properly update counters)
    #
    # The entry_identifier is used to lookup the @base_entry for the job (a.k.a. the entry the job was called from).
    # The @base_entry defines the context of the relationship (e.g. "this entry (@base_entry) should have a parent").
    # Whether the @base_entry is the parent or the child in the relationship is determined by the presence of a
    # parent_identifier or child_identifier param. For example, if a parent_identifier is passed, we know @base_entry
    # is the child in the relationship, and vice versa if a child_identifier is passed.
    def perform(parent_identifier:, importer_run_id:)
      pending_relationships = Bulkrax::PendingRelationship.where(bulkrax_importer_run_id: importer_run_id,
                                                                 parent_id: parent_identifier).sort_by(&:order)
      @importer_run_id = importer_run_id
      @parent_record = find_record(parent_identifier)
      @child_records = { works: [], collections: [] }
      pending_relationships.each do |rel|
        raise ::StandardError, %("#{rel}" needs either a child or a parent to create a relationship) if rel.child_id.nil? || rel.parent_id.nil?
        child_record = find_record(rel.child_id)
        child_record.is_a?(::Collection) ? @child_records[:collections] << child_record : @child_records[:works] << child_record
      end

      if (child_records[:collections].blank? && child_records[:works].blank?) || parent_record.blank?
        reschedule(
          parent_identifier: parent_identifier,
          importer_run_id: importer_run_id
        )
        return false # stop current job from continuing to run after rescheduling
      end


      @parent_entry = Bulkrax::Entry.where(identifier: parent_identifier,
                                           importerexporter_id: ImporterRun.find(importer_run_id).importer_id,
                                           importerexporter_type: "Bulkrax::Importer").first
      create_relationships
    rescue ::StandardError => e
      parent_record.status_info(e)
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
      ActiveSupport::Deprecation.warn(
        'Creating Collections using the collection_field_mapping will no longer be supported as of Bulkrax version 3.0.' \
        ' Please configure Bulkrax to use related_parents_field_mapping and related_children_field_mapping instead.'
      )
      child_records[:works].each do |child_record|
        attrs = { id: child_record.id, member_of_collections_attributes: { 0 => { id: parent_record.id } } }
        ObjectFactory.new(
          attributes: attrs,
          source_identifier_value: nil, # sending the :id in the attrs means the factory doesn't need a :source_identifier_value
          work_identifier: parent_entry.parser.work_identifier,
          collection_field_mapping: parent_entry.parser.collection_field_mapping,
          replace_files: false,
          user: user,
          klass: child_record.class
        ).run
        # TODO: add counters for :processed_parents and :failed_parents
        Bulkrax::ImporterRun.find(importer_run_id).increment!(:processed_relationships) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    # Collection-Collection membership is added to the as member_ids
    def collection_parent_collection_child
      ActiveSupport::Deprecation.warn(
        'Creating Collections using the collection_field_mapping will no longer be supported as of Bulkrax version 3.0.' \
        ' Please configure Bulkrax to use related_parents_field_mapping and related_children_field_mapping instead.'
      )
      child_records[:collections]
      attrs = { id: parent_record.id, child_collection_id: child_record.id }
      ObjectFactory.new(
        attributes: attrs,
        source_identifier_value: nil, # sending the :id in the attrs means the factory doesn't need a :source_identifier_value
        work_identifier: parent_entry.parser.work_identifier,
        collection_field_mapping: parent_entry.parser.collection_field_mapping,
        replace_files: false,
        user: user,
        klass: parent_record.class
      ).run
      # TODO: add counters for :processed_parents and :failed_parents
      Bulkrax::ImporterRun.find(importer_run_id).increment!(:processed_relationships) # rubocop:disable Rails/SkipsModelValidations
    end

    # Work-Work membership is added to the parent as member_ids
    def work_parent_work_child
      ActiveSupport::Deprecation.warn(
        'Creating Collections using the collection_field_mapping will no longer be supported as of Bulkrax version 3.0.' \
        ' Please configure Bulkrax to use related_parents_field_mapping and related_children_field_mapping instead.'
      )

      records_hash = {}
      child_records[:works].each_with_index do |child_record, i|
        records_hash[i] = { id: child_record.id }
      end
      attrs = {
        id: parent_record.id,
        work_members_attributes: records_hash
      }
      ObjectFactory.new(
        attributes: attrs,
        source_identifier_value: nil, # sending the :id in the attrs means the factory doesn't need a :source_identifier_value
        work_identifier: parent_entry.parser.work_identifier,
        collection_field_mapping: parent_entry.parser.collection_field_mapping,
        replace_files: false,
        user: user,
        klass: parent_record.class
      ).run
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
