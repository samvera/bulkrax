# frozen_string_literal: true

module Bulkrax
  class MissingParentError < ::StandardError; end
  class InvalidParentError < ::StandardError; end

  class ImportFileSetJob < ApplicationJob
    include DynamicRecordLookup
    include RetriesThenCountsFailure

    FAILED_COUNTER = :failed_file_sets

    queue_as Bulkrax.config.ingest_queue_name

    attr_reader :importer_run_id

    def perform(entry_id, importer_run_id)
      @importer_run_id = importer_run_id
      entry = Entry.find(entry_id)
      # e.g. "parents" or "parents_1"
      parent_identifier = (entry.raw_metadata[entry.related_parents_raw_mapping] || entry.raw_metadata["#{entry.related_parents_raw_mapping}_1"])&.strip

      begin
        validate_parent!(parent_identifier)
      rescue MissingParentError => e
        handle_retry(entry, importer_run_id, e)
        return
      rescue InvalidParentError => e
        count_as_failed(entry.id, importer_run_id, e)
        return
      end

      entry.build
      entry.save!
      ImporterRun.transaction do
        if entry.succeeded?
          # rubocop:disable Rails/SkipsModelValidations
          ImporterRun.increment_counter(:processed_records, importer_run_id)
          ImporterRun.increment_counter(:processed_file_sets, importer_run_id)
        else
          ImporterRun.increment_counter(:failed_records, importer_run_id)
          ImporterRun.increment_counter(:failed_file_sets, importer_run_id)
          # rubocop:enable Rails/SkipsModelValidations
        end
        ImporterRun.decrement_enqueued_records(importer_run_id)
        entry.importer.current_run = ImporterRun.find(importer_run_id)
        entry.importer.record_status
      end
    end

    private

    attr_reader :parent_record

    def validate_parent!(parent_identifier)
      # if parent_identifier is missing, it will be caught by #validate_presence_of_parent!
      return if parent_identifier.blank?

      find_parent_record(parent_identifier)
      check_parent_is_a_work!(parent_identifier)
    end

    def check_parent_is_a_work!(parent_identifier)
      case parent_record
      when Bulkrax.collection_model_class, Bulkrax.file_model_class
        error_msg = %(A record with the ID "#{parent_identifier}" was found, but it was a #{parent_record.class}, which is not an valid/available work type)
        raise InvalidParentError, error_msg
      end
    end

    def find_parent_record(parent_identifier)
      _, @parent_record = find_record(parent_identifier, importer_run_id)
      raise MissingParentError, %(Unable to find a record with the identifier "#{parent_identifier}") unless parent_record
    end

    def handle_retry(entry, importer_run_id, e)
      entry.import_attempts += 1
      entry.save!
      # Waits 5, 10, 20, 40 and then 80 minutes, outlasting a parent work's own retries.
      if entry.import_attempts < 6
        ImportFileSetJob.set(wait: (5 * (2**(entry.import_attempts - 1))).minutes).perform_later(entry.id, importer_run_id)
      else
        count_as_failed(entry.id, importer_run_id, e)
      end
    end
  end
end
