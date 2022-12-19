# frozen_string_literal: true

module Bulkrax
  class ImportWorkJob < ApplicationJob
    queue_as :import

    # rubocop:disable Rails/SkipsModelValidations
    def perform(entry_id, run_id, time_to_live = 3, *)
      entry = Entry.find(entry_id)
      importer_run = ImporterRun.find(run_id)
      entry.build
      if entry.status == "Complete"
        importer_run.increment!(:processed_records)
        importer_run.increment!(:processed_works)
      else
        # do not retry here because whatever parse error kept you from creating a work will likely
        # keep preventing you from doing so.
        importer_run.increment!(:failed_records)
        importer_run.increment!(:failed_works)
      end
      # Regardless of completion or not, we want to decrement the enqueued records.
      importer_run.decrement!(:enqueued_records) unless importer_run.enqueued_records <= 0

      entry.save!
      entry.importer.current_run = importer_run
      entry.importer.record_status
    rescue Bulkrax::CollectionsCreatedError => e
      Rails.logger.warn("#{self.class} entry_id: #{entry_id}, run_id: #{run_id} encountered #{e.class}: #{e.message}")
      # You get 3 attempts at the above perform before we have the import exception cascade into
      # the Sidekiq retry ecosystem.
      # rubocop:disable Style/IfUnlessModifier
      if time_to_live <= 1
        raise "Exhauted reschedule limit for #{self.class} entry_id: #{entry_id}, run_id: #{run_id}.  Attemping retries"
      end
      # rubocop:enable Style/IfUnlessModifier
      reschedule(entry_id, run_id, time_to_live)
    end
    # rubocop:enable Rails/SkipsModelValidations

    def reschedule(entry_id, run_id, time_to_live)
      ImportWorkJob.set(wait: 1.minute).perform_later(entry_id, run_id, time_to_live - 1)
    end
  end
end
