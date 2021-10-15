# frozen_string_literal: true

module Bulkrax
  class ParentNotFoundError < RuntimeError; end
  class ParentRelationshipsJob < RelationshipsJob
    def perform(*args)
      @args = args

      add_parent_relationships
    rescue ParentNotFoundError
      reschedule(args[0], args[1], args[2])
    end

    private

    def add_parent_relationships
      parent_identifiers.each do |p_id|
        parent_record = find_parent_record!(p_id)

        if parent_record.is_a?(::Collection)
          create_collection_relationship(parent_record)
        else
          create_work_relationship(parent_record)
        end
      end
    end

    def parent_identifiers
      @args[1]
    end

    def find_parent_record!(parent_identifier)
      parent_record = Entry.find_by(identifier: parent_identifier)
      parent_record ||= ::Collection.where(id: parent_identifier).first
      if parent_record.blank?
        ::Hyrax.config.curation_concerns.each do |work_type|
          parent_record ||= work_type.where(parent_identifier).first
        end
      end
      parent_record = parent_record.factory.find if parent_record.is_a?(Entry)

      return parent_record if parent_record.present?

      raise ParentNotFoundError, %(the record with identifier "#{parent_identifier}" could not be found)
    end

    def create_collection_relationship(parent_record)
      if child_record.is_a?(::Collection)
        collection_parent_collection_child(parent_id: parent_record.id, child_ids: [child_record&.id])
      else
        collection_parent_work_child(parent_id: parent_record.id, child_id: child_record&.id)
      end
    end

    def create_work_relationship(parent_record)
      raise ::StandardError, 'a Collection may not be assigned as a child of a Work' if child_record.is_a?(::Collection)

      work_parent_work_child(parent_id: parent_record.id, child_ids: [child_record&.id])
    end

    def child_record
      @child_record ||= entry.factory.find
    end

    def reschedule(child_entry_id, parent_identifiers, importer_run_id)
      ParentRelationshipsJob.set(wait: 10.minutes).perform_later(child_entry_id, parent_identifiers, importer_run_id)
    end
  end
end
