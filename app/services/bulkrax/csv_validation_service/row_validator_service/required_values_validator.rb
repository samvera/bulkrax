# frozen_string_literal: true

module Bulkrax
  class CsvValidationService::RowValidatorService::RequiredValuesValidator
    attr_reader :csv_data, :field_metadata

    def initialize(csv_data, field_metadata)
      @csv_data = csv_data
      @field_metadata = field_metadata
    end

    def validate
      return [] if @field_metadata.blank?

      errors = []

      csv_data.each_with_index do |row, index|
        model = row[:model]
        metadata = @field_metadata[model]
        next if metadata.blank?

        required_terms = metadata[:required_terms] || []
        required_terms.each do |field|
          next if row[:raw_row][field].present?

          errors << {
            row: index + 2,
            source_identifier: row[:source_identifier],
            severity: 'error',
            category: 'missing_required_value',
            column: field,
            value: nil,
            message: "Field '#{field}' is required but is empty for this row.",
            suggestion: "Add a value for '#{field}' in row #{index + 1}."
          }
        end
      end

      errors
    end
  end
end
