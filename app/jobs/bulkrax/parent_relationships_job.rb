# frozen_string_literal: true

module Bulkrax
  class ParentMissingError < RuntimeError; end
  class ParentRelationshipsJob < RelationshipsJob
    def perform(*args)
      @args = args
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

        case related_record.class
        when Entry
          case related_record.factory.find.class
          when ::Collection
            create_collection_relationship
          when ::NilClass # the entry's record has not been created yet
            raise ParentMissingError
          else
            create_work_relationship
          end
        when ::Collection
          create_collection_relationship
        else
          create_work_relationship
        end
      end
    end

    def parent_identifiers
      @args[1]
    end

    def create_collection_relationship
      # TODO
    end

    def create_work_relationship
      # TODO
    end

    private

    def reschedule(child_id, parent_identifiers, importer_run_id)
      ParentRelationshipsJob.set(wait: 10.minutes).perform_later(child_id, parent_identifiers, importer_run_id)
    end
  end
end
