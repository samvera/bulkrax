# frozen_string_literal: true

module Bulkrax
  class CsvValidationService::RowValidatorService::InvalidRelationshipValidator
    attr_reader :csv_data

    def initialize(csv_data)
      @csv_data = csv_data
    end

    def validate
      valid_identifiers = csv_data.map { |row| row[:source_identifier] }.to_set
      errors = []

      csv_data.each_with_index do |row, index|
        next if row[:parent].blank?

        parents = row[:parent].to_s.split('|').map(&:strip).reject(&:blank?)
        parents.each do |parent_id|
          next if valid_identifiers.include?(parent_id)

          errors << {
            row: index + 2,
            source_identifier: row[:source_identifier],
            severity: 'error',
            category: 'invalid_parent_reference',
            column: 'parent',
            value: parent_id,
            message: "Referenced parent '#{parent_id}' does not exist as a source_identifier in this CSV.",
            suggestion: 'Check for typos or add the parent record.'
          }
        end
      end

      errors
    end
  end
end
