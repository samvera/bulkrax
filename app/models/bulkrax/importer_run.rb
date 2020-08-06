# frozen_string_literal: true

module Bulkrax
  class ImporterRun < ApplicationRecord
    belongs_to :importer

    def importer_status
      import_run = importer.importer_runs.last

      return "Processing" if import_run&.enqueued_records&.positive?
      return "Completed (with failures)" if import_run&.failed_records&.positive? || import_run&.failed_collections&.positive? || import_run&.failed_children&.positive? || import_run&.invalid_records&.present?
      return "Completed" if import_run&.enqueued_records&.zero? && import_run&.processed_records == import_run&.total_work_entries
    end
  end
end
