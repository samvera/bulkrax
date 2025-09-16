# frozen_string_literal: true

module Bulkrax
  class DeleteAndImportJob < ApplicationJob
    queue_as :import

    def perform(entry, importer_run)
      # Delete the object if it exists, then reimport it.
      # If the object doesn't exist, just reimport it.
      begin
        status = self.class::DELETE_CLASS.perform_now(entry, importer_run)
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
      self.class::IMPORT_CLASS.perform_now(entry.id, importer_run.id)
    end
  end
end
