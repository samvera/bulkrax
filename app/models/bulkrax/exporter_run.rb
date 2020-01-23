# frozen_string_literal: true

module Bulkrax
  class ExporterRun < ApplicationRecord
    belongs_to :exporter

    def exporter_status
      export_runs = exporter.exporter_runs.last

      return "Failed" if export_runs&.processed_records&.zero?
      return "Complete" if export_runs&.enqueued_records&.zero? && export_runs&.processed_records == export_runs&.total_work_entries
      return "Complete (with failures)" if export_runs&.failed_records&.positive?
      return "Not yet exported" unless File.exist?(exporter.exporter_export_zip_path) || export_runs&.total_work_entries&.zero?
    end
  end
end
