module Bulkrax
  class ImportWorkJob < ApplicationJob
    queue_as :import

    def perform(*args)
      @importer = Importer.find(args[0])
      @importer_run = ImporterRun.find(args[1])
      begin
        @importer.import_work(args[2])
      rescue => e
        @importer_run.update_attribute(:failed_records, @importer_run.failed_records + 1)
        raise e
      else
        @importer_run.update_attribute(:processed_records, @importer_run.processed_records + 1)
      end
    end
  end
end
