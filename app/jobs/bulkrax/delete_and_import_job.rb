# frozen_string_literal: true

module Bulkrax
  class DeleteAndImportJob < ApplicationJob
    include RetriesThenCountsFailure

    queue_as :import

    def perform(entry, importer_run)
      # Delete the object if it exists, then reimport it.
      # If the object doesn't exist, just reimport it.
      begin
        delete_job = self.class::DELETE_CLASS.new(entry, importer_run)
        delete_job.reimport = true
        # #perform rather than #perform_now, so a failed delete raises here and this
        # job's retries count the record, instead of the delete job retrying alone.
        status = delete_job.perform(entry, importer_run)
        reimport(entry, importer_run) if status.status_message == "Deleted"
      rescue Bulkrax::ObjectFactoryInterface::ObjectNotFoundError
        reimport(entry, importer_run)
      end

    rescue => e
      entry.set_status_info(e)
      # this causes caught exception to be reraised
      raise
    end

    def reimport(entry, importer_run)
      entry = Bulkrax::Entry.find(entry.id) # maximum reload
      # Back to Pending so ScheduleRelationshipsJob waits for the reimport.
      entry.set_status_info('Pending', importer_run)
      self.class::IMPORT_CLASS.perform_now(entry.id, importer_run.id)
    end

    def failed_counter
      self.class::IMPORT_CLASS::FAILED_COUNTER
    end
  end
end
