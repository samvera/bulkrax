# frozen_string_literal: true

module Bulkrax
  class ExportWorkJob < ApplicationJob
    queue_as :export

    def perform(*args)
      entry = Entry.find(args[0])
      begin
        entry.build
        entry.save
      rescue StandardError => e
        ExporterRun.find(args[1]).increment!(:failed_records)
        ExporterRun.find(args[1]).decrement!(:enqueued_records)
        raise e
      else
        if entry.last_exception
          ExporterRun.find(args[1]).increment!(:failed_records)
          ExporterRun.find(args[1]).decrement!(:enqueued_records)
          raise entry.last_exception
        else
          ExporterRun.find(args[1]).increment!(:processed_records)
          ExporterRun.find(args[1]).decrement!(:enqueued_records)
        end
      end
    end
  end
end
