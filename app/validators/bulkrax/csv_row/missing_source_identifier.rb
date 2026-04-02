# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Validates that each row has a value for source_identifier unless
    # fill_in_blank_source_identifiers is configured (in which case Bulkrax
    # will generate one automatically).
    module MissingSourceIdentifier
      def self.call(record, row_index, context)
        return if Bulkrax.fill_in_blank_source_identifiers.present?
        return if record[:source_identifier].present?

        source_id_label = context[:source_identifier] || 'source_identifier'

        context[:errors] << {
          row: row_index,
          source_identifier: nil,
          severity: 'error',
          category: 'missing_source_identifier',
          column: source_id_label,
          value: nil,
          message: I18n.t('bulkrax.importer.guided_import.validation.missing_source_identifier_validator.errors.message',
                          field: source_id_label),
          suggestion: I18n.t('bulkrax.importer.guided_import.validation.missing_source_identifier_validator.errors.suggestion',
                             field: source_id_label)
        }
      end
    end
  end
end
