# frozen_string_literal: true

module Bulkrax
  class DeleteWorkJob < ApplicationJob
    queue_as :import

    # rubocop:disable Rails/SkipsModelValidations
    def perform(entry, importer_run)
      work = entry.factory.find
      work&.delete
      (importer_run.id ? ImporterRun.find(importer_run.id) : importer_run).increment!(:deleted_records)
      (importer_run.id ? ImporterRun.find(importer_run.id) : importer_run).decrement!(:enqueued_records)
      entry.save!
      entry.importer.current_run = (importer_run.id ? ImporterRun.find(importer_run.id) : importer_run)
      entry.importer.record_status
      entry.status_info("Deleted", (importer_run.id ? ImporterRun.find(importer_run.id) : importer_run))
    end
    # rubocop:enable Rails/SkipsModelValidations
  end
end
