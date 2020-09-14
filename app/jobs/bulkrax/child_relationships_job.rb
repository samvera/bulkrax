# frozen_string_literal: true

module Bulkrax
  class ChildWorksError < RuntimeError; end
  class ChildRelationshipsJob < ApplicationJob
    queue_as :import

    def perform(*args)
      @args = args

      if entry.factory_class == Collection
        collection_membership
      else
        work_membership
      end
      # Not all of the Works/Collections exist yet; reschedule
    rescue Bulkrax::ChildWorksError
      reschedule(args[0], args[1], args[2])
    end

    def collection_membership
      # add collection to works
      member_of_collection = []
      child_works_hash.each { |k, v| member_of_collection << k if v[:class_name] != 'Collection' }
      member_of_collection.each { |work| work_child_collection_parent(work) }

      # add collections to collection
      members_collections = []
      child_works_hash.each { |k, v| members_collections << k if v[:class_name] == 'Collection' }
      collection_parent_collection_child(members_collections) if members_collections.present?
    end

    def work_membership
      # add works to work
      # reject any Collections, they can't be children of Works
      members_works = []
      # reject any Collections, they can't be children of Works
      child_works_hash.each { |k, v| members_works << k if v[:class_name] != 'Collection' }
      if members_works.length < child_entries.length # rubocop:disable Style/IfUnlessModifier
        Rails.logger.warn("Cannot add collections as children of works: #{(@child_entries.length - members_works.length)} collections were discarded for parent entry #{@entry.id} (of #{@child_entries.length})")
      end
      work_parent_work_child(members_works) if members_works.present?
    end

    def entry
      @entry ||= Bulkrax::Entry.find(@args[0])
    end

    def child_entries
      @child_entries ||= @args[1].map { |e| Bulkrax::Entry.find(e) }
    end

    def child_works_hash
      @child_works_hash ||= child_entries.each_with_object({}) do |child_entry, hash|
        work = child_entry.factory.find
        # If we can't find the Work/Collection, raise a custom error
        raise ChildWorksError if work.blank?
        hash[work.id] = { class_name: work.class.to_s, source_identifier: child_entry.identifier }
      end
    end

    def importer_run_id
      @args[2]
    end

    def user
      @user ||= entry.importerexporter.user
    end

    private

      # rubocop:disable Rails/SkipsModelValidations
      # Work-Collection membership is added to the child as member_of_collection_ids
      # This is adding the reverse relatinship, from the child to the parent
      def work_child_collection_parent(work_id)
        attrs = { id: work_id, collections: [{ id: entry&.factory&.find&.id }] }
        Bulkrax::ObjectFactory.new(attrs, child_works_hash[work_id][:source_identifier], false, user, child_works_hash[work_id][:class_name].constantize).run
        ImporterRun.find(importer_run_id).increment!(:processed_children)
      rescue StandardError => e
        entry.status_info(e)
        ImporterRun.find(importer_run_id).increment!(:failed_children)
      end

      # Collection-Collection membership is added to the as member_ids
      def collection_parent_collection_child(member_ids)
        attrs = { id: entry&.factory&.find&.id, children: member_ids }
        Bulkrax::ObjectFactory.new(attrs, entry.identifier, false, user, entry.factory_class).run
        ImporterRun.find(importer_run_id).increment!(:processed_children)
      rescue StandardError => e
        entry.status_info(e)
        ImporterRun.find(importer_run_id).increment!(:failed_children)
      end

      # Work-Work membership is added to the parent as member_ids
      def work_parent_work_child(member_ids)
        # build work_members_attributes
        attrs = { id: entry&.factory&.find&.id,
                  work_members_attributes: member_ids.each.with_index.each_with_object({}) do |(member, index), ids|
                    ids[index] = { id: member }
                  end }
        Bulkrax::ObjectFactory.new(attrs, entry.identifier, false, user, entry.factory_class).run
        ImporterRun.find(importer_run_id).increment!(:processed_children)
      rescue StandardError => e
        entry.status_info(e)
        ImporterRun.find(importer_run_id).increment!(:failed_children)
      end
      # rubocop:enable Rails/SkipsModelValidations

      def reschedule(entry_id, child_entry_ids, importer_run_id)
        ChildRelationshipsJob.set(wait: 10.minutes).perform_later(entry_id, child_entry_ids, importer_run_id)
      end
  end
end
