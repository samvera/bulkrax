# frozen_string_literal: true

module Bulkrax
  class DeleteWorkJob < ApplicationJob
    queue_as :import

    # rubocop:disable Rails/SkipsModelValidations
    def perform(entry, importer_run)
      work = entry.factory.find
      work&.delete
      importer_run.increment!(:deleted_records)
      importer_run.decrement!(:enqueued_records)
    end
    # rubocop:enable Rails/SkipsModelValidations
  end
end
