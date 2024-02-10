# frozen_string_literal: true

module Bulkrax
  class DeleteAndImportJob < ApplicationJob
    queue_as :import

    def perform(entry, importer_run)
      status = self.class::DELETE_CLASS.perform_now(entry, importer_run)
      if status.status_message == "Deleted"
        entry = Bulkrax::Entry.find(entry.id) # maximum reload
        self.class::IMPORT_CLASS.perform_now(entry.id, importer_run.id)
      end

    rescue => e
      entry.set_status_info(e)
      # this causes caught exception to be reraised
      raise
    end
  end
end
