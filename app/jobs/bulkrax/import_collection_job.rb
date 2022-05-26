# frozen_string_literal: true

module Bulkrax
  class ImportCollectionJob < ApplicationJob
    queue_as :import

    # rubocop:disable Rails/SkipsModelValidations
    def perform(*args)
      entry = Entry.find(args[0])
      begin
        entry.build
        entry.save!
        ImporterRun.find(args[1]).increment!(:processed_records)
        ImporterRun.find(args[1]).increment!(:processed_collections)
        ImporterRun.find(args[1]).decrement!(:enqueued_records) unless ImporterRun.find(args[1]).enqueued_records <= 0 # rubocop:disable Style/IdenticalConditionalBranches
      rescue => e
        ImporterRun.find(args[1]).increment!(:failed_records)
        ImporterRun.find(args[1]).increment!(:failed_collections)
        ImporterRun.find(args[1]).decrement!(:enqueued_records) unless ImporterRun.find(args[1]).enqueued_records <= 0 # rubocop:disable Style/IdenticalConditionalBranches
        raise e
      end
      entry.importer.current_run = ImporterRun.find(args[1])
      entry.importer.record_status
    end
    # rubocop:enable Rails/SkipsModelValidations
  end
end
