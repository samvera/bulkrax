# frozen_string_literal: true

module Bulkrax
  class ParentMissingError < RuntimeError; end
  class ParentRelationshipsJob < RelationshipsJob
    def perform(*args)
      @args = args

      add_parent_relationships
    rescue ParentMissingError
      reschedule(args[0], args[1], args[2])
    end

    private

    def add_parent_relationships
      parent_identifiers.each do |p_id|
        related_record = find_related_record!(p_id)
        related_record_class = related_record.is_a?(Entry) ? related_record.factory.find.class : related_record.class

        case related_record_class
        when ::NilClass
          raise ParentMissingError, "the record for entry #{related_record&.identifier} has not been created yet"
        when ::Collection
          create_collection_relationship(related_record)
        else
          create_work_relationship(related_record)
        end
      end
    end

    def parent_identifiers
      @args[1]
    end

    def find_related_record!(parent_identifier)
      related_record = Entry.find_by(identifier: parent_identifier)
      related_record ||= ::Collection.find(parent_identifier)
      if related_record.blank?
        ::Hyrax.config.curation_concerns.each do |work_type|
          related_record ||= work_type.constantize.find(parent_identifier)
        end
      end
      return related_record if related_record.present?

      raise ParentMissingError, "the record with identifier #{parent_identifier} could not be found"
    end

    def create_collection_relationship(related_record)
      if child_object.is_a?(::Collection)
        collection_parent_collection_child(parent_id: related_record.id, child_ids: [child_object&.id])
      else
        collection_parent_work_child(parent_id: related_record.id, child_id: child_object&.id)
      end
    end

    def create_work_relationship
      raise ::StandardError, 'a Collection may not be assigned as a child of a Work' if child_object.is_a?(::Collection)

      work_parent_work_child(parent_id: related_record.id, child_ids: [child_object&.id])
    end

    def child_object
      @child_object ||= entry.factory.find
    end

    def reschedule(child_id, parent_identifiers, importer_run_id)
      ParentRelationshipsJob.set(wait: 10.minutes).perform_later(child_id, parent_identifiers, importer_run_id)
    end
  end
end
