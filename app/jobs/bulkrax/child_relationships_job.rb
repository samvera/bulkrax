# frozen_string_literal: true

module Bulkrax
  class ChildRelationshipsJob < RelationshipsJob
    def perform(*args)
      @args = args

      if entry.factory_class == Collection
        collection_membership
      else
        work_membership
      end
      # Not all of the Works/Collections exist yet; reschedule
    rescue ChildNotFoundError
      reschedule(args[0], args[1], args[2])
    end

    def collection_membership
      # add collection to works
      member_of_collection = []
      child_records_hash.each { |k, v| member_of_collection << k if v[:class_name] != 'Collection' }
      member_of_collection.each { |work_id| collection_parent_work_child(parent_id: entry&.factory&.find&.id, child_id: work_id) }

      # add collections to collection
      members_collections = []
      child_records_hash.each { |k, v| members_collections << k if v[:class_name] == 'Collection' }
      collection_parent_collection_child(parent_id: entry&.factory&.find&.id, child_ids: members_collections) if members_collections.present?
    end

    def work_membership
      # add works to work
      # reject any Collections, they can't be children of Works
      members_works = []
      # reject any Collections, they can't be children of Works
      child_records_hash.each { |k, v| members_works << k if v[:class_name] != 'Collection' }
      if members_works.length < child_entries.length # rubocop:disable Style/IfUnlessModifier
        Rails.logger.warn("Cannot add collections as children of works: #{(@child_entries.length - members_works.length)} collections were discarded for parent entry #{@entry.id} (of #{@child_entries.length})")
      end
      work_parent_work_child(parent_id: entry&.factory&.find&.id, child_ids: members_works) if members_works.present?
    end

    def child_entries
      @child_entries ||= @args[1].map do |e|
        Entry.find_by(identifier: e) || Entry.find(e)
      end
    end

    def parent_entries
      @parent_entries ||= [entry]
    end

    private

    def reschedule(entry_id, child_entry_ids, importer_run_id)
      ChildRelationshipsJob.set(wait: 10.minutes).perform_later(entry_id, child_entry_ids, importer_run_id)
    end
  end
end
