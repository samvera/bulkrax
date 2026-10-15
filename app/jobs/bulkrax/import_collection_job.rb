# frozen_string_literal: true

module Bulkrax
  class ImportCollectionJob < ApplicationJob
    include RetriesThenCountsFailure

    FAILED_COUNTER = :failed_collections

    queue_as Bulkrax.config.ingest_queue_name

    # rubocop:disable Rails/SkipsModelValidations
    def perform(*args)
      entry = Entry.find(args[0])
      entry.build
      entry.save!
      # An entry that fails inside #build records the error on itself rather
      # than raising, so its status is what says whether this run succeeded.
      ImporterRun.transaction do
        if entry.succeeded?
          ImporterRun.increment_counter(:processed_records, args[1])
          ImporterRun.increment_counter(:processed_collections, args[1])
        else
          ImporterRun.increment_counter(:failed_records, args[1])
          ImporterRun.increment_counter(:failed_collections, args[1])
        end
        ImporterRun.decrement_enqueued_records(args[1])
        entry.importer.current_run = ImporterRun.find(args[1])
        entry.importer.record_status
      end
    end
    # rubocop:enable Rails/SkipsModelValidations
  end
end
