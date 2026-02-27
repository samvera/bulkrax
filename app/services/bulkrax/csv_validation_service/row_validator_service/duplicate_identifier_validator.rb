# frozen_string_literal: true

module Bulkrax
  class CsvValidationService::RowValidatorService::DuplicateIdentifierValidator
    include Bulkrax::CsvValidationService::RowValidatorService::ValidatorHelpers

    attr_reader :csv_data, :manager_mapper

    def initialize(csv_data, manager_mapper = nil)
      @csv_data = csv_data
      @manager_mapper = manager_mapper
    end

    def validate(errors)
      first_seen_at_row = {}

      each_row do |row, row_number|
        source_identifier = row[:source_identifier]

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
    end

    private

    def source_identifier_label
      manager_mapper&.find_by_flag(:source_identifier, nil) || 'source_identifier'
    end
  end
end
