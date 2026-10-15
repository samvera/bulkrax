# frozen_string_literal: true

module Bulkrax
  class ImportWorkJob < ApplicationJob
    queue_as Bulkrax.config.ingest_queue_name

    # rubocop:disable Rails/SkipsModelValidations
    #
    # @note Counters change through single SQL updates ({ImporterRun.increment_counter},
    #       {ImporterRun.decrement_enqueued_records}), never by loading the run and saving it.
    #       Jobs run concurrently, so a load-and-save would overwrite another job's count.
    #
    # @see https://codingdeliberately.com/activerecord-increment/
    # @see https://github.com/samvera-labs/bulkrax/commit/5c2c795452e13a98c9217fdac81ae2f5aea031a0#r105848236
    def perform(entry_id, run_id, time_to_live = 3, *)
      entry = Entry.find(entry_id)
      entry.build
      if entry.status == "Complete"
        ImporterRun.increment_counter(:processed_records, run_id)
        ImporterRun.increment_counter(:processed_works, run_id)
      else
        # do not retry here because whatever parse error kept you from creating a work will likely
        # keep preventing you from doing so.
        ImporterRun.increment_counter(:failed_records, run_id)
        ImporterRun.increment_counter(:failed_works, run_id)
      end
      # Regardless of completion or not, we want to decrement the enqueued records.
      ImporterRun.decrement_enqueued_records(run_id)

      entry.save!
      entry.importer.current_run = ImporterRun.find(run_id)
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
