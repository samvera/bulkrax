# frozen_string_literal: true

module Bulkrax
  class CsvValidationService::RowValidatorService::ControlledVocabularyValidator
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

        controlled_terms = metadata[:controlled_vocab_terms] || []
        next if controlled_terms.blank?

        controlled_terms.each do |field|
          value = row[:raw_row][field]
          next if value.blank?

          authority = load_authority(field)
          next if authority.nil?

          term = authority.find(value)
          next if term&.dig('active') == true

          errors << {
            row: index + 1,
            source_identifier: row[:source_identifier],
            severity: 'error',
            category: 'invalid_controlled_value',
            column: field,
            value: value,
            message: "'#{value}' is not a recognized term for '#{field}'.",
            suggestion: "Check the controlled vocabulary for valid terms."
          }
        end
      end

      errors
    end

    private

    def load_authority(field)
      Qa::Authorities::Local.subauthority_for(field.pluralize)
    rescue Qa::InvalidSubAuthority
      Qa::Authorities::Local.subauthority_for(field)
    rescue Qa::InvalidSubAuthority
      nil
    end
  end
end
