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

    def add_parent_relationships
      parent_identifiers.each do |p_id|
        related_record = Entry.find_by(identifier: p_id)
        related_record ||= ::Collection.find(p_id)
        if related_record.blank?
          ::Hyrax.config.curation_concerns.each do |work_type|
            related_record ||= work_type.constantize.find(p_id)
          end
        end

        raise ParentMissingError if related_record.blank?

        related_record_class = related_record.is_a?(Entry) ? related_record.factory.find.class : related_record.class
        case related_record_class
        when ::NilClass # the entry's record has not been created yet
          raise ParentMissingError
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

    def create_collection_relationship(related_record)
      child_object = entry.factory.find # TODO: make method?

      if child_object.is_a?(::Collection)
        collection_parent_collection_child(parent_id: related_record.id, child_ids: [child_object&.id])
      else
        collection_parent_work_child(parent_id: related_record.id, child_id: child_object&.id)
      end
    end

    def create_work_relationship
      raise ::StandardError, 'A Collection may not be assigned as a child of a Work' if entry.factory.find.is_a?(::Collection)

      # TODO: child_ids must be a hash? see #child_works_hash
      work_parent_work_child(parent_id: related_record.id, child_ids: entry.factory.find&.id)
    end

    private

    def reschedule(child_id, parent_identifiers, importer_run_id)
      ParentRelationshipsJob.set(wait: 10.minutes).perform_later(child_id, parent_identifiers, importer_run_id)
    end
  end
end
