# frozen_string_literal: true

module Bulkrax
  class ExportWorkJob < ApplicationJob
    queue_as :export

    def perform(*args)
      entry = Entry.find(args[0])
      exporter_run = ExporterRun.find(args[1])
      begin
        entry.build
        entry.save
      rescue StandardError
        # rubocop:disable Rails/SkipsModelValidations
        exporter_run.increment!(:failed_records)
        exporter_run.decrement!(:enqueued_records) unless exporter_run.enqueued_records <= 0
        raise
      else
        if entry.failed?
          exporter_run.increment!(:failed_records)
          exporter_run.decrement!(:enqueued_records) unless exporter_run.enqueued_records <= 0
          raise entry.reload.current_status.error_class.constantize
        else
          exporter_run.increment!(:processed_records)
          exporter_run.decrement!(:enqueued_records) unless exporter_run.enqueued_records <= 0
        end
        # rubocop:enable Rails/SkipsModelValidations
      end
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
