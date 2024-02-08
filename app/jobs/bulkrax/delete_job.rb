# frozen_string_literal: true

module Bulkrax
  class DeleteJob < ApplicationJob
    queue_as :import

    def perform(entry, importer_run)
      obj = entry.factory.class.find(entry.raw_metadata["id"])

      if defined?(Valkyrie) && obj.class < Valkyrie::Resource
        Hyrax.persister.delete(resource: obj)
        Hyrax.index_adapter.delete(resource: obj)
        Hyrax.publisher.publish('object.deleted', object: obj, user: importer_run.importer.user)
      else
        obj&.delete
      end

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
