module Bulkrax
  class ImportWorkJob < ApplicationJob
    queue_as :import

    def perform(*args)
      @importer = Importer.find(args[0])
      @importer.import_work(args[1])
      @importer.current_importer_run.update_attribute(:processed_records, @importer.current_importer_run + 1)
    end
  end
end
