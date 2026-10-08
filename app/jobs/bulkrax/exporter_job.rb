# frozen_string_literal: true

module Bulkrax
  class ExporterJob < ApplicationJob
    queue_as :export

    def perform(exporter_id)
      exporter = Exporter.find(exporter_id)
      exporter.export
      write(exporter)
      exporter.save
      true
    end

    private

    # Each entry's ExportWorkJob sets the exporter's status as the last one finishes. So an export
    # that matched no records, or whose last entry raised, never gets a status and would read Pending
    # forever, and a failure while writing the files would leave it reading Complete with nothing to
    # download.
    def write(exporter)
      exporter.write
      return if exporter.current_status

      exporter.set_status_info(exporter.last_run.reload.failed_records.to_i.positive? ? 'Complete (with failures)' : nil)
    rescue StandardError => e
      exporter.set_status_info(e)
      raise
    end
  end
end
