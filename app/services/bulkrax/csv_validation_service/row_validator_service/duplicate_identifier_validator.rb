# frozen_string_literal: true

module Bulkrax
  class CsvValidationService::RowValidatorService::DuplicateIdentifierValidator
    attr_reader :csv_data

    def initialize(csv_data)
      @csv_data = csv_data
    end

    def validate
      first_seen_at_row = {}
      errors = []

      csv_data.each_with_index do |row, index|
        source_identifier = row[:source_identifier]
        row_number = index + 1

        if first_seen_at_row[source_identifier]
          errors << {
            row: row_number,
            source_identifier: source_identifier,
            severity: 'error',
            category: 'duplicate_source_identifier',
            column: 'source_identifier',
            value: source_identifier,
            message: "Duplicate source_identifier '#{source_identifier}' — also appears in row #{first_seen_at_row[source_identifier]}.",
            suggestion: 'Each source_identifier must be unique within the CSV.'
          }
        else
          first_seen_at_row[source_identifier] = row_number
        end
      end

      errors
    end
  end
end
