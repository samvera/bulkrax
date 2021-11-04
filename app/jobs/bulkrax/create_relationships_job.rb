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
    queue_as :import

    attr_accessor :base_entry, :child_record, :parent_record, :importer_run

    # @param entry_identifier [String] source_identifier of the base Bulkrax::Entry the job was triggered from (see #build_for_importer)
    # @param parent_identifier [String] Work/Collection ID or Bulkrax::Entry source_identifier
    # @param child_identifier [String] Work/Collection ID or Bulkrax::Entry source_identifier
    # @param importer_run [Bulkrax::ImporterRun] current importer run (needed to properly update counters)
    #
    # The entry_identifier is used to lookup the @base_entry for the job (a.k.a. the entry the job was called from).
    # The @base_entry defines the context of the relationship (e.g. "this entry (@base_entry) should have a parent").
    # Whether the @base_entry is the parent or the child in the relationship is determined by the presence of a
    # parent_identifier or child_identifier param. For example, if a parent_identifier is passed, we know @base_entry
    # is the child in the relationship, and vice versa if a child_identifier is passed.
    def perform(entry_identifier:, parent_identifier: nil, child_identifier: nil, importer_run:)
      @base_entry = Entry.find_by(identifier: entry_identifier)
      @importer_run = importer_run
      if parent_identifier.present?
        @child_record = find_record(entry_identifier)
        @parent_record = find_record(parent_identifier)
      elsif child_identifier.present?
        @parent_record = find_record(entry_identifier)
        @child_record = find_record(child_identifier)
      else
        raise ::StandardError, %("#{entry_identifier}" needs either a child or a parent to create a relationship)
      end

      if @child_record.blank? || @parent_record.blank?
        reschedule(
          entry_identifier: entry_identifier,
          parent_identifier: parent_identifier,
          child_identifier: child_identifier,
          importer_run: importer_run
        )
      end

      create_relationship
    rescue ::StandardError => e
      base_entry.status_info(e)
      importer_run.increment!(:failed_children) # rubocop:disable Rails/SkipsModelValidations
    end

    private

    def create_relationship
      if parent_record.is_a?(::Collection) && child_record.is_a?(::Collection)
        collection_parent_collection_child
      elsif parent_record.is_a?(::Collection) && curation_concern?(child_record)
        collection_parent_work_child
      elsif curation_concern?(parent_record) && child_record.is_a?(::Collection)
        raise ::StandardError, 'a Collection may not be assigned as a child of a Work'
      else
        work_parent_work_child
      end
    end

    # This method allows us to create relationships with preexisting records (by their ID) OR
    # with records that are concurrently being imported (by their Bulkrax::Entry source_identifier).
    #
    # @param identifier [String] Work/Collection ID or Bulkrax::Entry source_identifier
    # @return [Work, Collection, nil] Work or Collection if found, otherwise nil
    def find_record(identifier)
      record = Entry.find_by(identifier: identifier)
      record ||= ::Collection.where(id: identifier).first
      if record.blank?
        available_work_types.each do |work_type|
          record ||= work_type.where(id: identifier).first
        end
      end
      record = record.factory.find if record.is_a?(Entry)

      record
    end

    # Check if the record is a Work
    def curation_concern?(record)
      available_work_types.include?(record.class)
    end

    # @return [Array<Class>] list of work type classes
    def available_work_types
      # If running in a Hyku app, do not reference disabled work types
      @available_work_types ||= if defined?(::Hyku)
                                  ::Site.instance.available_works.map(&:constantize)
                                else
                                  ::Hyrax.config.curation_concerns
                                end
    end

    def user
      @user ||= importer_run.importer.user
    end

    # Work-Collection membership is added to the child as member_of_collection_ids
    # This is adding the reverse relationship, from the child to the parent
    def collection_parent_work_child
      attrs = { id: child_record.id, member_of_collections_attributes: { 0 => { id: parent_record.id } } }
      # TODO: add resulting record's id to base_entry's parsed_metadata?
      ObjectFactory.new(
        attributes: attrs,
        source_identifier_value: nil, # sending the :id in the attrs means the factory doesn't need a :source_identifier_value
        work_identifier: base_entry.parser.work_identifier,
        collection_field_mapping: base_entry.parser.collection_field_mapping,
        replace_files: false,
        user: user,
        klass: child_record.class
      ).run
      # TODO: add counters for :processed_parents and :failed_parents
      importer_run.increment!(:processed_children) # rubocop:disable Rails/SkipsModelValidations
    end

    # Collection-Collection membership is added to the as member_ids
    def collection_parent_collection_child
      attrs = { id: parent_record.id, child_collection_id: child_record.id }
      # TODO: add resulting record's id to base_entry's parsed_metadata?
      ObjectFactory.new(
        attributes: attrs,
        source_identifier_value: nil, # sending the :id in the attrs means the factory doesn't need a :source_identifier_value
        work_identifier: base_entry.parser.work_identifier,
        collection_field_mapping: base_entry.parser.collection_field_mapping,
        replace_files: false,
        user: user,
        klass: parent_record.class
      ).run
      # TODO: add counters for :processed_parents and :failed_parents
      importer_run.increment!(:processed_children) # rubocop:disable Rails/SkipsModelValidations
    end

    # Work-Work membership is added to the parent as member_ids
    def work_parent_work_child
      attrs = {
        id: parent_record.id,
        work_members_attributes: { 0 => { id: child_record.id } }
      }
      # TODO: add resulting record's id to base_entry's parsed_metadata?
      ObjectFactory.new(
        attributes: attrs,
        source_identifier_value: nil, # sending the :id in the attrs means the factory doesn't need a :source_identifier_value
        work_identifier: base_entry.parser.work_identifier,
        collection_field_mapping: base_entry.parser.collection_field_mapping,
        replace_files: false,
        user: user,
        klass: parent_record.class
      ).run
      # TODO: add counters for :processed_parents and :failed_parents
      importer_run.increment!(:processed_children) # rubocop:disable Rails/SkipsModelValidations
    end

    def reschedule(entry_identifier:, parent_identifier:, child_identifier:, importer_run:)
      CreateRelationshipsJob.set(wait: 10.minutes).perform_later(
        entry_identifier: entry_identifier,
        parent_identifier: parent_identifier,
        child_identifier: child_identifier,
        importer_run: importer_run
      )
    end
  end
end
