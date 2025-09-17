# frozen_string_literal: true

module Bulkrax
  class DeleteFileSetJob < DeleteJob
    def perform(entry, importer_run)
      # Ensure the entry has metadata built for delete if it
      # doesn't already so it can be found for deletion.
      if entry.respond_to?(:build_metadata_for_delete) &&
         entry.parsed_metadata.nil? &&
         entry.raw_metadata.present?
        entry.build_metadata_for_delete
        entry.save!
      end
      file_set = entry.factory.find

      if file_set
        parent = file_set.parent
        if parent&.respond_to?(:ordered_members)
          om = parent.ordered_members.to_a
          om.delete(file_set)
          parent.ordered_members = om
          parent.save
        elsif parent&.respond_to?(:member_ids)
          parent.member_ids.delete(file_set.id)
          Hyrax.persister.save(resource: parent)
        end
      end

      super
    end
  end
end
