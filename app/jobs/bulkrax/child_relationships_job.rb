module Bulkrax
  class ChildRelationshipsJob < ApplicationJob
    queue_as :import

    def perform(*args)
      entry = Entry.find(args[0])
      child_entries = args[1].map { |e| Entry.find(e) }

      # @todo - 
      # reschedule if works exist - which means checking if factory.find.id is nil
      # deal with any errors - what might we get?
      # move out of Job?
      # add counts to importer runs?
      if entry.factory_class.is_a?(Collection)
        # Work-Collection membership is added to the Work with member_of_collection_ids
        collection_members = child_entries.reject { | ce | ce.factory_class.is_a?(Collection) }
        collection_members.each do | work_entry |
          member_of_collection_ids = work_entry.find.member_of_collection_ids.push(entry.find.id).uniq
          Bulkrax::ObjectFactory.new({ member_of_collection_ids: member_of_collection_ids }, work_entry.identifier, nil, work_entry.factory_class).run
        end
        # Collection-Collection membership is added to parent with members_ids
        members = child_entries.select { | ce | ce.factory_class.is_a?(Collection) }
        collection_ids = entry.find.member_ids.concat(members.map { |c| c.factory.find.id }.compact).uniq
        Bulkrax::ObjectFactory.new({ member_ids: collection_ids }, entry.identifier, nil, entry.factory_class).run
      else
        # Work-Work membership is added to parent with child_work_ids
        # reject any Collections, they can't be children of Works
        child_entries = child_entries.reject { | ce | ce.factory_class.is_a?(Collection) }
        work_ids = entry.find.child_work_ids.concat(child_entries.map { |w| w.factory.find.id }.compact).uniq
        Bulkrax::ObjectFactory.new({ child_work_ids: work_ids }, entry.identifier, nil, entry.factory_class).run
      end
        # Exceptions here are not an issue with adding the relationships.
        # Those are caught seperately, these are more likely network, db or other unexpected issues.
        # Note that these temporary type issues do not raise the failure count
      rescue StandardError => e
        raise e
    end

    def reschedule(entry_id, child_entry_ids)
      ChildRelationshipsJob.set(wait: 1.minutes).perform_later(entry_id, run_id)
    end

  end
end
