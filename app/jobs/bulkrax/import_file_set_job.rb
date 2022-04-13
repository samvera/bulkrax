# frozen_string_literal: true

module Bulkrax
  class MissingParentError < ::StandardError; end
  class ImportFileSetJob < ApplicationJob
    include DynamicRecordLookup

    queue_as :import

    attr_reader :importer_run_id

    def perform(entry_id, importer_run_id)
      @importer_run_id = importer_run_id
      entry = Entry.find(entry_id)
      parent_identifier = entry.raw_metadata[entry.related_parents_raw_mapping]&.strip

      validate_parent!(parent_identifier)

      entry.build
      if entry.succeeded?
        # rubocop:disable Rails/SkipsModelValidations
        ImporterRun.find(importer_run_id).increment!(:processed_records)
        ImporterRun.find(importer_run_id).increment!(:processed_file_sets)
      else
        ImporterRun.find(importer_run_id).increment!(:failed_records)
        ImporterRun.find(importer_run_id).increment!(:failed_file_sets)
        # rubocop:enable Rails/SkipsModelValidations
      end
      ImporterRun.find(importer_run_id).decrement!(:enqueued_records) # rubocop:disable Rails/SkipsModelValidations
      entry.save!

    rescue MissingParentError => e
      # try waiting for the parent record to be created
      entry.import_attempts += 1
      entry.save!
      if entry.import_attempts < 5
        ImportFileSetJob
          .set(wait: (entry.import_attempts + 1).minutes)
          .perform_later(entry_id, importer_run_id)
      else
        ImporterRun.find(importer_run_id).decrement!(:enqueued_records) # rubocop:disable Rails/SkipsModelValidations
        entry.status_info(e)
      end
    end

    private

    attr_reader :parent_record

    def validate_parent!(parent_identifier)
      # if parent_identifier is missing, it will be caught by #validate_presence_of_parent!
      return if parent_identifier.blank?

      find_parent_record(parent_identifier)
      check_parent_exists!(parent_identifier)
      check_parent_is_a_work!(parent_identifier)
    end

    def check_parent_exists!(parent_identifier)
      raise MissingParentError, %(Unable to find a record with the identifier "#{parent_identifier}") if parent_record.blank?
    end

    def check_parent_is_a_work!(parent_identifier)
      error_msg = %(A record with the ID "#{parent_identifier}" was found, but it was a #{parent_record.class}, which is not an valid/available work type)
      raise ::StandardError, error_msg unless curation_concern?(parent_record)
    end

    def find_parent_record(parent_identifier)
      @parent_record ||= find_record(parent_identifier, importer_run_id)
      @parent_record = parent_record.last if parent_record.is_a? Array
    end
  end
end
