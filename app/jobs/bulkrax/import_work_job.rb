module Bulkrax
  class ImportWorkJob < ApplicationJob
    queue_as :import

    def perform(*args)
      entry = Entry.find(args[0])
      begin
        entry.build
        entry.save
      rescue => e
        ImporterRun.find(args[1]).increment!(:failed_records)
        raise e
      else
        ImporterRun.find(args[1]).increment!(:processed_records)
      end
    end
  end
end
