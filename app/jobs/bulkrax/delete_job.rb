# frozen_string_literal: true

module Bulkrax
  class DeleteJob < ApplicationJob
    queue_as Bulkrax.config.ingest_queue_name

    def perform(entry, importer_run)
      user = importer_run.importer.user
      entry.factory.delete(user)

      # rubocop:disable Rails/SkipsModelValidations
      ImporterRun.increment_counter(:deleted_records, importer_run.id)
      ImporterRun.decrement_counter(:enqueued_records, importer_run.id)
      # rubocop:enable Rails/SkipsModelValidations
      entry.save!
      entry.importer.current_run = ImporterRun.find(importer_run.id)
      entry.importer.record_status
      entry.set_status_info("Deleted", ImporterRun.find(importer_run.id))
    rescue => e
      entry.set_status_info(e)
      # this causes caught exception to be reraised
      raise
    end
  end
end
