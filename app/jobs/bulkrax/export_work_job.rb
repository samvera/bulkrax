# frozen_string_literal: true

module Bulkrax
  class ExportWorkJob < ApplicationJob
    queue_as :export

    def perform(*args)
      entry = Entry.find(args[0])
      begin
        entry.build
        entry.save
      rescue StandardError
        # rubocop:disable Rails/SkipsModelValidations
        ExporterRun.find(args[1]).increment!(:failed_records)
        ExporterRun.find(args[1]).decrement!(:enqueued_records)
        raise
      else
        if entry.failed?
          ExporterRun.find(args[1]).increment!(:failed_records)
          ExporterRun.find(args[1]).decrement!(:enqueued_records)
          raise entry.reload.current_status.error_class.constantize
        else
          ExporterRun.find(args[1]).increment!(:processed_records)
          ExporterRun.find(args[1]).decrement!(:enqueued_records)
        end
        # rubocop:enable Rails/SkipsModelValidations
      end
      exporter_run = ExporterRun.find(args[1])
      return entry if exporter_run.enqueued_records.positive?
      if exporter_run.failed_records.positive?
        exporter_run.exporter.status_info('Complete (with failures)')
      else
        exporter_run.exporter.status_info('Complete')
      end
      return entry
    end
  end
end
