# frozen_string_literal: true

module Bulkrax
  class ImportFileSetJob < ApplicationJob
    queue_as :import

    def perform(*args)
      entry = Entry.find(args[0])
      begin
        entry.build
        entry.save
        # rubocop:disable Rails/SkipsModelValidations
        ImporterRun.find(args[1]).increment!(:processed_file_sets)
        ImporterRun.find(args[1]).decrement!(:enqueued_records)
      rescue => e
        ImporterRun.find(args[1]).increment!(:failed_file_sets)
        ImporterRun.find(args[1]).decrement!(:enqueued_records)
        # rubocop:enable Rails/SkipsModelValidations
        raise e
      end
    end
  end
end
