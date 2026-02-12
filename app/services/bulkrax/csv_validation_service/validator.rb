# frozen_string_literal: true

module Bulkrax
  class CsvValidationService
    ##
    # Validates CSV structure and content against model schemas
    #
    # Responsibilities:
    # - Identify missing required fields
    # - Find unrecognized CSV headers
    # - Determine overall validity
    # - Detect warnings (unrecognized headers, missing files)
    #
    # @example
    #   validator = Validator.new(csv_headers, valid_headers, field_metadata, mapping_manager)
    #   validator.missing_required_fields  # => [{model: 'Work', field: 'title'}]
    #   validator.unrecognized_headers     # => ['invalid_column']
    #   validator.valid?                   # => false
    #
    class Validator
      # Initialize the validator
      #
      # @param csv_headers [Array<String>] Headers from the CSV file
      # @param valid_headers [Array<String>] Valid headers for the models
      # @param field_metadata [Hash] Metadata about fields for each model
      # @param mapping_manager [SampleCsvService::MappingManager] Field mapping manager
      # @param file_validator [FileValidator] Optional file validator for warnings
      def initialize(csv_headers, valid_headers, field_metadata, mapping_manager, file_validator = nil)
        @csv_headers = csv_headers || []
        @valid_headers = valid_headers || []
        @field_metadata = field_metadata || {}
        @mapping_manager = mapping_manager
        @file_validator = file_validator
      end

      # Find required fields that are missing from the CSV
      #
      # @return [Array<Hash>] Array of hashes with :model and :field keys
      def missing_required_fields
        @missing_required_fields ||= begin
          csv_hdrs = @csv_headers.map { |h| @mapping_manager.mapped_to_key(h) }

          missing = []
          @field_metadata.each do |model, metadata|
            required = metadata[:required_terms] || []
            model_missing = required - csv_hdrs
            missing += model_missing.map { |field| { model: model, field: field } }
          end

          missing.uniq
        end
      end

      # Find headers in CSV that are not recognized as valid fields
      #
      # @return [Array<String>] Array of unrecognized header names
      def unrecognized_headers
        @unrecognized_headers ||= @csv_headers - @valid_headers
      end

      # Check if CSV is valid (no missing required fields and has headers)
      #
      # @return [Boolean] True if valid
      def valid?
        missing_required_fields.empty? && @csv_headers.present?
      end

      # Check if CSV has warnings (unrecognized headers or missing files)
      #
      # @return [Boolean] True if there are warnings
      def warnings?
        unrecognized_headers.any? || (@file_validator&.missing_files&.any? || false)
      end
    end
  end
end
