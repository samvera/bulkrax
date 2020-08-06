# frozen_string_literal: true

module Bulkrax
  class ExporterRun < ApplicationRecord
    belongs_to :exporter

    def exporter_status
      export_run = exporter.exporter_runs.last

      return "Processing" if export_run&.enqueued_records&.positive?
      return "Failed" if export_run&.processed_records&.zero?
      return "Complete" if export_run&.enqueued_records&.zero? && export_run&.processed_records == export_run&.total_work_entries
      return "Complete (with failures)" if export_run&.failed_records&.positive?
      return "Not yet exported" unless File.exist?(exporter.exporter_export_zip_path) || export_run&.total_work_entries&.zero?
    end
  end
end
