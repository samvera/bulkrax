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
      # @param mapping_manager [CsvValidationService::MappingManager] Field mapping manager
      # @param file_validator [CsvValidationService::FileValidator] Optional file validator for warnings
      def initialize(csv_headers, valid_headers, field_metadata, mapping_manager, file_validator = nil)
        @csv_headers = csv_headers || []
        @valid_headers = valid_headers || []
        @field_metadata = field_metadata || {}
        @mapping_manager = mapping_manager
        @file_validator = file_validator
      end

      # Find required fields that are missing from the CSV
      # Headers with numeric suffixes (_1, _2, etc.) are normalized before checking
      # (e.g., 'title_1' satisfies the 'title' requirement)
      #
      # @return [Array<Hash>] Array of hashes with :model and :field keys
      def missing_required_fields
        @missing_required_fields ||= begin
          # Map headers through field mappings and normalize suffixes
          csv_hdrs = @csv_headers.map { |h| normalize_header(@mapping_manager.mapped_to_key(h)) }.uniq

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
      # Headers with numeric suffixes (_1, _2, etc.) are normalized to their base form
      # before comparison (e.g., 'creator_1' is treated as 'creator')
      #
      # @return [Array<String>] Array of unrecognized header names
      def unrecognized_headers
        @unrecognized_headers ||= @csv_headers
                                  .reject { |h| @valid_headers.include?(h) || @valid_headers.include?(normalize_header(h)) }
                                  .index_with { |h| spell_checker.correct(h).first }
      end

      # Check if CSV is valid (no missing required fields and has headers)
      #
      # @return [Boolean] True if valid
      def valid?
        !errors?
      end

      # Check if CSV has warnings (unrecognized headers or missing files)
      #
      # @return [Boolean] True if there are warnings
      def warnings?
        unrecognized_headers.any? || (@file_validator&.possible_missing_files? || false)
      end

      def errors?
        missing_required_fields.any? || @csv_headers.blank? || (@file_validator&.missing_files&.any? || false)
      end

      private

      # Normalize a header by stripping numeric suffixes
      # Handles multi-valued fields where CSV columns like 'creator_1', 'creator_2'
      # should be recognized as valid if 'creator' is a valid field
      #
      # @param header [String] The header to normalize
      # @return [String] The normalized header (without numeric suffix)
      #
      # @example
      #   normalize_header('creator_1')   # => 'creator'
      #   normalize_header('title_2')     # => 'title'
      #   normalize_header('source_identifier') # => 'source_identifier'
      def normalize_header(header)
        header.sub(/_\d+\z/, '')
      end

      def spell_checker
        DidYouMean::SpellChecker.new(dictionary: @valid_headers)
      end
    end
  end
end
