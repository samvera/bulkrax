# frozen_string_literal: true

module Bulkrax
  class ImportCollectionJob < ApplicationJob
    queue_as Bulkrax.config.ingest_queue_name

    # rubocop:disable Rails/SkipsModelValidations
    def perform(*args)
      entry = Entry.find(args[0])
      begin
        entry.build
        entry.save!
        # An entry that fails inside #build records the error on itself rather
        # than raising, so its status is what says whether this run succeeded.
        if entry.succeeded?
          ImporterRun.increment_counter(:processed_records, args[1])
          ImporterRun.increment_counter(:processed_collections, args[1])
        else
          ImporterRun.increment_counter(:failed_records, args[1])
          ImporterRun.increment_counter(:failed_collections, args[1])
        end
        ImporterRun.decrement_counter(:enqueued_records, args[1]) unless ImporterRun.find(args[1]).enqueued_records <= 0 # rubocop:disable Style/IdenticalConditionalBranches
      rescue => e
        ImporterRun.increment_counter(:failed_records, args[1])
        ImporterRun.increment_counter(:failed_collections, args[1])
        ImporterRun.decrement_counter(:enqueued_records, args[1]) unless ImporterRun.find(args[1]).enqueued_records <= 0 # rubocop:disable Style/IdenticalConditionalBranches
        raise e
      end
      entry.importer.current_run = ImporterRun.find(args[1])
      entry.importer.record_status
    end
    # rubocop:enable Rails/SkipsModelValidations
  end
end
