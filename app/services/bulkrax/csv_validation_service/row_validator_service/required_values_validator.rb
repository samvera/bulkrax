# frozen_string_literal: true

module Bulkrax
  class CsvValidationService::RowValidatorService::RequiredValuesValidator
    include Bulkrax::CsvValidationService::RowValidatorService::ValidatorHelpers

    attr_reader :csv_data, :field_metadata

    def initialize(csv_data, field_metadata)
      @csv_data = csv_data
      @field_metadata = field_metadata
    end

    def validate(errors)
      return if @field_metadata.blank?

      each_row do |row, row_number|
        model = row[:model]
        metadata = @field_metadata[model]
        next if metadata.blank?

        required_terms = metadata[:required_terms] || []
        required_terms.each do |field|
          next if row[:raw_row][field].present?

          errors << {
            row: row_number,
            source_identifier: row[:source_identifier],
            severity: 'error',
            category: 'missing_required_value',
            column: field,
            value: nil,
            message: I18n.t('bulkrax.importer.guided_import.validation.required_field_validator.errors.message', field: field),
            suggestion: I18n.t('bulkrax.importer.guided_import.validation.required_field_validator.errors.suggestion', field: field)
          }
        end
      end
    end
  end
end
