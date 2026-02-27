# frozen_string_literal: true

module Bulkrax
  class CsvValidationService::RowValidatorService::InvalidRelationshipValidator
    include Bulkrax::CsvValidationService::RowValidatorService::ValidatorHelpers

    attr_reader :csv_data, :manager_mapper

    def initialize(csv_data, manager_mapper = nil)
      @csv_data = csv_data
      @manager_mapper = manager_mapper
    end

    def validate(errors)
      valid_identifiers = csv_data.map { |row| row[:source_identifier] }.to_set

      each_row do |row, row_number|
        parents = row[:parent]
        next if parents.blank?

        parents = parents.split(split_value).map(&:strip).reject(&:blank?) if split?
        Array.wrap(parents).each do |parent_id|
          next if valid_identifiers.include?(parent_id)

          errors << {
            row: row_number,
            source_identifier: row[:source_identifier],
            severity: 'error',
            category: 'invalid_parent_reference',
            column: 'parent',
            value: parent_id,
            message: I18n.t('bulkrax.importer.guided_import.validation.parent_reference_validator.errors.message',
                            value: parent_id,
                            field: 'source_identifier'),
            suggestion: I18n.t('bulkrax.importer.guided_import.validation.parent_reference_validator.errors.suggestion')
          }
        end
      end
    end

    private

    def split?
      manager_mapper&.split_value_for(:parent).present?
    end

    def split_value
      value = manager_mapper&.split_value_for(:parent)
      return value unless value == true

      Bulkrax::DEFAULT_MULTI_VALUE_ELEMENT_SPLIT_ON
    end
  end
end
