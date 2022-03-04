module Bulkrax
  class ScheduleRelationshipsJob < ApplicationJob

    def perform(importer_id:)
      importer = Importer.find(importer_id)
      pending_num = Bulkrax::Status.where(statusable_type: "Bulkrax::Entry",
                                          statusable_id: importer.entry_ids).where.not(status_message: "Complete").count
      return reschedule(importer_id) unless pending_num.zero?

      importer.last_run.parents.each do |parent_id|
        CreateRelationshipsJob.perform_later(parent_identifier: parent_id, importer_run_id: importer.last_run.id)
      end
    end

    def reschedule(importer_id)
      ScheduleRelationshipsJob.set(wait: 1.minutes).perform_later(importer_id: importer_id)
      false
    end

  end
end
