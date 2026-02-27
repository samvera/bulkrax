# frozen_string_literal: true

module Bulkrax
  class CsvValidationService::RowValidatorService::DuplicateIdentifierValidator
    attr_reader :csv_data, :source_identifier_label, :manager_mapper

    def initialize(csv_data, manager_mapper = nil)
      @csv_data = csv_data
      @manager_mapper = manager_mapper
      @source_identifier_label = source_identifier_label_lookup
    end

    def validate
      first_seen_at_row = {}
      errors = []

      csv_data.each_with_index do |row, index|
        source_identifier = row[:source_identifier]
        row_number = index + 2

        if first_seen_at_row[source_identifier]
          errors << {
            row: row_number,
            source_identifier: source_identifier,
            severity: 'error',
            category: 'duplicate_source_identifier',
            column: source_identifier_label,
            value: source_identifier,
            message: I18n.t('bulkrax.importer.guided_import.validation.duplicate_identifier_validator.errors.message',
                            value: source_identifier,
                            field: source_identifier_label,
                            original_row: first_seen_at_row[source_identifier]),
            suggestion: I18n.t('bulkrax.importer.guided_import.validation.duplicate_identifier_validator.errors.suggestion',
                              field: source_identifier_label)
          }
        else
          first_seen_at_row[source_identifier] = row_number
        end
      end

      errors
    end

    private

    def source_identifier_label_lookup
      manager_mapper&.find_by_flag(:source_identifier, nil) || 'source_identifier'
    end
  end
end
