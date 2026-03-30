# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Validates that each row has a unique source_identifier.
    # Uses context[:seen_ids] (Hash: id => first_seen_row_number) to detect duplicates.
    module DuplicateIdentifier
      def self.call(record, row_index, context)
        source_id = record[:source_identifier]
        return if source_id.blank? && Bulkrax.fill_in_blank_source_identifiers.present?

        source_id_label = context[:source_identifier] || 'source_identifier'
        first_row = context[:seen_ids][source_id]

        if first_row
          context[:errors] << {
            row: row_index,
            source_identifier: source_id,
            severity: 'error',
            category: 'duplicate_source_identifier',
            column: source_id_label,
            value: source_id,
            message: I18n.t('bulkrax.importer.guided_import.validation.duplicate_identifier_validator.errors.message',
                            value: source_id,
                            field: source_id_label,
                            original_row: first_row),
            suggestion: I18n.t('bulkrax.importer.guided_import.validation.duplicate_identifier_validator.errors.suggestion',
                               field: source_id_label)
          }
        else
          context[:seen_ids][source_id] = row_index
        end
      end
    end
  end
end
