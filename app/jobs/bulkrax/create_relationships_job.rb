# frozen_string_literal: true

module Bulkrax
  class ChildNotFoundError < RuntimeError; end
  class ParentNotFoundError < RuntimeError; end
  class CreateRelationshipsJob < ApplicationJob
    queue_as :import

    attr_accessor :entry, :child_record, :parent_record, :importer_run

    def perform(entry_identifier:, parent_identifier: nil, child_identifier: nil, importer_run:)
      @entry = Entry.find_by(identifier: entry_identifier)
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

      if @parent_record.is_a?(::Collection) && @child_record.is_a?(::Collection)
        collection_parent_collection_child
      elsif @parent_record.is_a?(::Collection) && curation_concern?(@child_record)
        collection_parent_work_child
      elsif curation_concern?(@parent_record) && @child_record.is_a?(::Collection)
        raise ActiveFedora::RecordInvalid, 'a Collection may not be assigned as a child of a Work'
      else
        work_parent_work_child
      end
    end

    private

    def find_record(identifier)
      record = Entry.find_by(identifier: identifier)
      record ||= ::Collection.where(id: identifier).first
      if record.blank?
        ::Hyrax.config.curation_concerns.each do |work_type|
          record ||= work_type.where(identifier).first
        end
      end
      record = record.factory.find if record.is_a?(Entry)

      record
    end

    def curation_concern?(record)
      ::Hyrax.config.curation_concerns.include?(record.class)
    end

    def user
      @user ||= importer_run.importer.user
    end

    # rubocop:disable Rails/SkipsModelValidations
    # Work-Collection membership is added to the child as member_of_collection_ids
    # This is adding the reverse relationship, from the child to the parent
    def collection_parent_work_child
      attrs = { id: child_record.id, member_of_collections_attributes: { 0 => { id: parent_record.id } } }
      # TODO: add resulting record's id to entry's parsed_metadata?
      ObjectFactory.new(attributes: attrs,
                        source_identifier_value: nil, # sending the :id in the attrs means the factory doesn't need a :source_identifier_value
                        work_identifier: entry.parser.work_identifier,
                        collection_field_mapping: entry.parser.collection_field_mapping,
                        replace_files: false,
                        user: user,
                        klass: child_record.class).run
      # TODO: add counters for :processed_parents and :failed_parents
      importer_run.increment!(:processed_children)
    rescue StandardError => e
      entry.status_info(e)
      importer_run.increment!(:failed_children)
    end

    # Collection-Collection membership is added to the as member_ids
    def collection_parent_collection_child
      attrs = { id: parent_record.id, children: child_record.id }
      # TODO: add resulting record's id to entry's parsed_metadata?
      ObjectFactory.new(attributes: attrs,
                        source_identifier_value: nil, # sending the :id in the attrs means the factory doesn't need a :source_identifier_value
                        work_identifier: entry.parser.work_identifier,
                        collection_field_mapping: entry.parser.collection_field_mapping,
                        replace_files: false,
                        user: user,
                        klass: parent_record.class).run
      # TODO: add counters for :processed_parents and :failed_parents
      importer_run.increment!(:processed_children)
    rescue StandardError => e
      entry.status_info(e)
      importer_run.increment!(:failed_children)
    end

    # Work-Work membership is added to the parent as member_ids
    def work_parent_work_child
      attrs = {
        id: parent_record.id,
        work_members_attributes: { 0 => { id: child_record.id } }
      }
      # TODO: add resulting record's id to entry's parsed_metadata?
      ObjectFactory.new(attributes: attrs,
                        source_identifier_value: nil, # sending the :id in the attrs means the factory doesn't need a :source_identifier_value
                        work_identifier: entry.parser.work_identifier,
                        collection_field_mapping: entry.parser.collection_field_mapping,
                        replace_files: false,
                        user: user,
                        klass: parent_record.class).run
      # TODO: add counters for :processed_parents and :failed_parents
      importer_run.increment!(:processed_children)
    rescue StandardError => e
      entry.status_info(e)
      importer_run.increment!(:failed_children)
    end
    # rubocop:enable Rails/SkipsModelValidations
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
