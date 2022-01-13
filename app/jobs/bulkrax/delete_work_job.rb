# frozen_string_literal: true

module Bulkrax
  class DeleteWorkJob < ApplicationJob
    queue_as :import

    # rubocop:disable Rails/SkipsModelValidations
    def perform(entry, importer_run)
      work = entry.factory.find
      work&.delete
      ImporterRun.find(importer_run.id).increment!(:deleted_records) || importer_run
      ImporterRun.find(importer_run.id).decrement!(:enqueued_records) || importer_run
      entry.save!
      entry.importer.current_run = ImporterRun.find(importer_run.id) || importer_run
      entry.importer.record_status
      entry.status_info("Deleted", ImporterRun.find(importer_run.id) || importer_run)
    end
    # rubocop:enable Rails/SkipsModelValidations
  end
end
