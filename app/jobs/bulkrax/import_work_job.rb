module Bulkrax
  class ImportWorkJob < ApplicationJob
    queue_as :import

    def perform(*args)
      @importer = Importer.find(args[0])
      begin
        @importer.import_work(args[2])
      rescue => e
        ImporterRun.find(args[1]).increment!(:failed_records)
        raise e
      else
        ImporterRun.find(args[1]).increment!(:processed_records)
      end
    end
  end
end
