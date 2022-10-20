# frozen_string_literal: true

module Bulkrax
  class ImportCollectionJob < ApplicationJob
    queue_as :import

    # rubocop:disable Rails/SkipsModelValidations
    # @param entry_id [Object] the key for the Bulkrax::Entry to build and save.
    # @param run_id [Object] the key for the Bulkrax::ImporterRun in which we're running this entry.
    #
    # @return [String]
    def perform(entry_id, run_id, *)
      entry = Entry.find(entry_id)
      importer_run = ImporterRun.find(run_id)
      begin
        entry.build
        entry.save!
        importer_run.increment!(:processed_records)
        importer_run.increment!(:processed_collections)
        importer_run.decrement!(:enqueued_records) unless importer_run.enqueued_records <= 0 # rubocop:disable Style/IdenticalConditionalBranches
      rescue => e
        importer_run.increment!(:failed_records)
        importer_run.increment!(:failed_collections)
        importer_run.decrement!(:enqueued_records) unless importer_run.enqueued_records <= 0 # rubocop:disable Style/IdenticalConditionalBranches
        raise e
      end
      entry.importer.current_run = importer_run
      entry.importer.record_status
    end
    # rubocop:enable Rails/SkipsModelValidations
  end
end
