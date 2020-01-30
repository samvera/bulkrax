# frozen_string_literal: true

module Bulkrax
  class ImporterRun < ApplicationRecord
    belongs_to :importer

    def importer_status
      import_runs = importer.importer_runs.last

      return "Failed" if import_runs&.failed_records&.positive? || import_runs&.failed_collections&.positive? || import_runs&.failed_children&.positive?
      return "Processing" if import_runs&.enqueued_records&.positive?
      return "Completed" if import_runs&.enqueued_records&.zero? && import_runs&.processed_records == import_runs&.total_work_entries
    end
  end
end
