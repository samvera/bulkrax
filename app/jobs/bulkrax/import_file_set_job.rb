# frozen_string_literal: true

module Bulkrax
  class ImportFileSetJob < ApplicationJob
    include DynamicRecordLookup

    queue_as :import

    def perform(*args)
      entry = Entry.find(args[0])
      parent_identifier = entry.raw_metadata[entry.related_parents_raw_mapping]
      raise StandardError, %(Unable to find a record with the identifier "#{parent_identifier}") if entry.import_attempts > 4

      if parent_identifier.present?
        parent_record = find_record(parent_identifier)
        if parent_record.blank? || parent_record.class == Entry # wait for parent record to be created
          entry.increment!(:import_attempts) # rubocop:disable Rails/SkipsModelValidations
          ImportFileSetJob.set(wait: (entry.import_attempts + 1).minutes).perform_later(*args)
          return
        end
      end

      entry.build
      entry.save
      # rubocop:disable Rails/SkipsModelValidations
      ImporterRun.find(args[1]).increment!(:processed_file_sets)
      ImporterRun.find(args[1]).decrement!(:enqueued_records)
    rescue => e
      ImporterRun.find(args[1]).increment!(:failed_file_sets)
      ImporterRun.find(args[1]).decrement!(:enqueued_records)
      # rubocop:enable Rails/SkipsModelValidations
      entry.status_info(e)
    end
  end
end
