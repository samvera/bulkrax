# frozen_string_literal: true

module Bulkrax
  class ImportWorkJob < ApplicationJob
    queue_as :import

    # rubocop:disable Rails/SkipsModelValidations
    def perform(entry_id, run_id, *)
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
    rescue Bulkrax::CollectionsCreatedError
      reschedule(entry_id, run_id)
    end
    # rubocop:enable Rails/SkipsModelValidations

    def reschedule(entry_id, run_id)
      ImportWorkJob.set(wait: 1.minute).perform_later(entry_id, run_id)
    end
  end
end
