# frozen_string_literal: true

module Bulkrax
  class ImporterRun < ApplicationRecord
    belongs_to :importer

    def importer_status
      import_runs = importer.importer_runs.last

      return "Failed" if import_runs&.failed_records > 0 || import_runs&.failed_collections > 0 || import_runs&.failed_children > 0
      return "Processing" if import_runs&.enqueued_records > 0
      return "Completed" if import_runs&.enqueued_records == 0 && import_runs&.processed_records == import_runs&.total_work_entries
    end
  end
end
