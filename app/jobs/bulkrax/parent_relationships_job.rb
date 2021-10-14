# frozen_string_literal: true

module Bulkrax
  class ParentMissingError < RuntimeError; end
  class ParentRelationshipsJob < ApplicationJob
    queue_as :import

    def perform(child_id, parent_identifiers, current_run_id)
      @child_id = child_id
      @parent_identifiers = parent_identifiers
      @current_run_id = current_run_id
    rescue ParentMissingError
      reschedule(child_id, parent_identifiers, current_run_id)
    end

    def add_parent_relationships
      @parent_identifiers.each do |p_id|
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

    def create_collection_relationship
      # TODO
    end

    def create_work_relationship
      # TODO
    end

    def entry
      @entry ||= Entry.find(@child_id)
    end

    private

    def reschedule(child_id, parent_identifiers, current_run_id)
      ParentRelationshipsJob.set(wait: 10.minutes).perform_later(child_id, parent_identifiers, current_run_id)
    end
  end
end
