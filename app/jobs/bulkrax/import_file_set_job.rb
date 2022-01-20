# frozen_string_literal: true

module Bulkrax
  class MissingParentError < ::StandardError; end
  class ImportFileSetJob < ApplicationJob
    include DynamicRecordLookup

    queue_as :import

    def perform(*args)
      entry = Entry.find(args[0])
      parent_identifier = entry.raw_metadata[entry.related_parents_raw_mapping]&.strip

      check_parent_exists!(parent_identifier)

      entry.build
      if entry.succeeded?
        # rubocop:disable Rails/SkipsModelValidations
        ImporterRun.find(args[1]).increment!(:processed_records)
        ImporterRun.find(args[1]).increment!(:processed_file_sets)
      else
        ImporterRun.find(args[1]).increment!(:failed_records)
        ImporterRun.find(args[1]).increment!(:failed_file_sets)
        # rubocop:enable Rails/SkipsModelValidations
      end
      ImporterRun.find(args[1]).decrement!(:enqueued_records) # rubocop:disable Rails/SkipsModelValidations
      entry.save!

    rescue MissingParentError => e
      # try waiting for the parent record to be created
      entry.import_attempts += 1
      entry.save!
      if entry.import_attempts < 5
        ImportFileSetJob.set(wait: (entry.import_attempts + 1).minutes).perform_later(*args)
      else
        entry.status_info(e)
      end
    end

    private

    def check_parent_exists!(parent_identifier)
      return if parent_identifier.blank?

      parent_record = find_record(parent_identifier)
      raise MissingParentError, %(Unable to find a record with the identifier "#{parent_identifier}") if parent_record.blank? || parent_record.class == Entry
    end
  end
end
