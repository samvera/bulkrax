module Bulkrax
  class ChildWorksError < Exception; end
  class ChildRelationshipsJob < ApplicationJob
    queue_as :import

    def perform(*args)
      begin
        @entry = Entry.find(args[0])
        @child_entries = args[1].map { |e| Entry.find(e) }
        @child_works_hash = build_child_works_hash
        @importer_run_id = args[2]
        @user = @entry.importerexporter.user

        if (@entry.factory_class == Collection)
          # add collection to works
          member_of_collection = []
          @child_works_hash.each_pair { |k,v| member_of_collection << k if v[:class_name] != 'Collection' }
          member_of_collection.each { |work| work_child_collection_parent(work) }

          # add collections to collection
          members_collections = []
          @child_works_hash.each_pair { |k,v| members_collections << k if v[:class_name] == 'Collection' }
          collection_parent_collection_child(members_collections) unless members_collections.blank?
        else
          # add works to work
          members_works = []
          # reject any Collections, they can't be children of Works
          @child_works_hash.each_pair {|k,v| members_works << k if v[:class_name] != 'Collection' }
          if members_works.length < @child_entries.length
            Rails.logger.warn("Cannot add collections as children of works: #{(@child_entries.length - members_works.length)} collections were discarded for parent entry #{@entry.id} (of #{@child_entries.length})")
          end
          work_parent_work_child(members_works) unless members_works.blank?
        end
      # Not all of the Works/Collections exist yet; reschedule
      rescue Bulkrax::ChildWorksError
        reschedule(args[0], args[1], args[2])
      end
    end

    private

    def build_child_works_hash
      hash = {}
      @child_entries.each do |child_entry|
        work = child_entry.factory.find
        # If we can't find the Work/Collection, raise a custom error
        raise ChildWorksError if work.blank?
        hash[work.id] = { class_name: work.class.to_s, source_identifier: child_entry.identifier }
      end
      return hash
    end

    # Work-Collection membership is added to the child as member_of_collection_ids
    # This is adding the reverse relatinship, from the child to the parent
    def work_child_collection_parent(work_id)
      attrs = { id: work_id, collections: [{ id: @entry.factory.find.id }] }
      Bulkrax::ObjectFactory.new(attrs, @child_works_hash[work_id][:source_identifier], false, @user, @child_works_hash[work_id][:class_name].constantize).run
      ImporterRun.find(@importer_run_id).increment!(:processed_children)
    rescue StandardError => e
      ImporterRun.find(@importer_run_id).increment!(:failed_children)
    end

    # Collection-Collection membership is added to the as member_ids
    def collection_parent_collection_child(member_ids)
      attrs = { id: @entry.factory.find.id, collections: member_ids }
      Bulkrax::ObjectFactory.new(attrs, @entry.identifier, false, @user, @entry.factory_class).run
      ImporterRun.find(@importer_run_id).increment!(:processed_children)
    rescue StandardError
      ImporterRun.find(@importer_run_id).increment!(:failed_children)
    end

    # Work-Work membership is added to the parent as member_ids
    def work_parent_work_child(member_ids)
      # build work_members_attributes
      attrs = { id: @entry.factory.find.id, 
        work_members_attributes: member_ids.each.with_index.inject({}) do |ids, (member, index)|
          ids[index] = { id: member }
          ids
        end
      }
      Bulkrax::ObjectFactory.new(attrs, @entry.identifier, false, @user, @entry.factory_class).run
      ImporterRun.find(@importer_run_id).increment!(:processed_children)
    rescue StandardError => e
      ImporterRun.find(@importer_run_id).increment!(:failed_children)
    end

    def reschedule(entry_id, child_entry_ids, importer_run_id)
      ChildRelationshipsJob.set(wait: 10.minutes).perform_later(entry_id, child_entry_ids, importer_run_id)
    end

  end
end
