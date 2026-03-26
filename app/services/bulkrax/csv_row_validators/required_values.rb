# frozen_string_literal: true

module Bulkrax
  module CsvRowValidators
    ##
    # Validates that each row provides a value for every required field of its model.
    # Numeric suffixes on column names are normalised before checking
    # (e.g. 'title_1' satisfies the 'title' requirement).
    module RequiredValues
      def self.call(record, row_index, context)
        field_metadata = context[:field_metadata]
        return if field_metadata.blank?

        model = record[:model]
        metadata = field_metadata[model]
        return if metadata.blank?

        required_terms = metadata[:required_terms] || []
        required_terms.each do |field|
          next if record[:raw_row].any? { |key, value| normalize_header(key.to_s) == field && value.present? }

          context[:errors] << {
            row: row_index,
            source_identifier: record[:source_identifier],
            severity: 'error',
            category: 'missing_required_value',
            column: field,
            value: nil,
            message: I18n.t('bulkrax.importer.guided_import.validation.required_field_validator.errors.message', field: field),
            suggestion: I18n.t('bulkrax.importer.guided_import.validation.required_field_validator.errors.suggestion', field: field)
          }
        end
      end

      def self.normalize_header(header)
        header.sub(/_\d+\z/, '')
      end
    end
  end
end
