# frozen_string_literal: true

module Bulkrax
  class ExporterRun < ApplicationRecord
    belongs_to :exporter

    def exporter_status
      export_runs = exporter.exporter_runs.last

      return "Failed" if export_runs&.processed_records == 0
      return "Complete" if export_runs&.enqueued_records == 0 && export_runs&.processed_records == export_runs&.total_work_entries
      return "Complete (with failures)" if export_runs&.failed_records > 0
      return "Not yet exported" unless File.exist?(exporter.exporter_export_zip_path) || export_runs&.total_work_entries == 0
    end
  end
end
