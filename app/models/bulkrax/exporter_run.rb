# frozen_string_literal: true

module Bulkrax
  class ExporterRun < ApplicationRecord
    belongs_to :exporter

    def exporter_status
      export_run = exporter.exporter_runs.last

      @exporter_status ||= if export_run&.enqueued_records&.positive?
                             'Processing'
                           elsif export_run&.processed_records&.zero?
                             'Failed'
                           elsif export_run&.failed_records&.positive?
                             'Complete (with failures)'
                           elsif export_run&.processed_records == export_run&.total_work_entries
                             'Complete'
                           else
                             'Pending'
                           end
    end
  end
end
