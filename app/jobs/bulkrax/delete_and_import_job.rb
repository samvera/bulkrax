# frozen_string_literal: true

module Bulkrax
  class DeleteAndImportJob < ApplicationJob
    queue_as :import

    cattr_accessor :delete_class, :import_class
    self.delete_class = Bulkrax::DeleteJob
    self.import_class = Bulkrax::ImportJob

    def perform(entry, importer_run)
      self.delete_class.perform_now(entry, importer_run)
      self.import_class.perform_now(entry.id, importer_run.id)
    end
  end
end
