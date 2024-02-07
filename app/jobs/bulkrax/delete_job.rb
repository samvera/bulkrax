# frozen_string_literal: true

module Bulkrax
  class DeleteJob < ApplicationJob
    queue_as :import

    def perform(entry, importer_run)
      obj = entry.factory.find
      obj&.delete
      # rubocop:disable Rails/SkipsModelValidations
      ImporterRun.increment_counter(:deleted_records, importer_run.id)
      ImporterRun.decrement_counter(:enqueued_records, importer_run.id)
      # rubocop:enable Rails/SkipsModelValidations
      entry.save!
      entry.importer.current_run = ImporterRun.find(importer_run.id)
      entry.importer.record_status
      entry.set_status_info("Deleted", ImporterRun.find(importer_run.id))
    end
  end
end
