module Bulkrax
  class ImportWorkJob < ApplicationJob
    queue_as :import

    def perform(*args)
      entry = Entry.find(args[0])
      begin
        if entry.build.present?
          entry.save
        else
          reschedule(entry.id, ImporterRun.find(args[1]).id)
        end
      rescue StandardError => e
        ImporterRun.find(args[1]).increment!(:failed_records)
        raise e
      else
        if entry.last_exception
          ImporterRun.find(args[1]).increment!(:failed_records)
          raise entry.last_exception
        else
          ImporterRun.find(args[1]).increment!(:processed_records)
        end
      end
    end

    def reschedule(entry_id, run_id)
      ImportWorkJob.set(wait: 1.minutes).perform_later(entry_id, run_id)
    end
  end
end
