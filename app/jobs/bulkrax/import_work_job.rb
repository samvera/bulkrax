module Bulkrax
  class ImportWorkJob < ApplicationJob
    queue_as :import

    def perform(*args)
      entry = Entry.find(args[0])
      build = entry.build
      entry.save
      if build == true
        ImporterRun.find(args[1]).increment!(:processed_records)
      elsif build == false && entry.last_exception.blank?
        reschedule(entry.id, ImporterRun.find(args[1]).id)
      elsif entry.last_exception.present?
        raise entry.last_exception
      end
      rescue StandardError => e
        ImporterRun.find(args[1]).increment!(:failed_records)
        raise e
    end

    def reschedule(entry_id, run_id)
      ImportWorkJob.set(wait: 1.minutes).perform_later(entry_id, run_id)
    end
  end
end
