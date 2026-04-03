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
          add_duplicate_error(context, row_index, source_id, source_id_label, first_row)
        else
          context[:seen_ids][source_id] = row_index
          add_existing_warning(context, row_index, source_id, source_id_label)
        end
      end

      def self.add_duplicate_error(context, row_index, source_id, source_id_label, first_row)
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
      end
      private_class_method :add_duplicate_error

      def self.add_existing_warning(context, row_index, source_id, source_id_label)
        find_record = context[:find_record_by_source_identifier]
        return unless find_record&.call(source_id)

        context[:errors] << {
          row: row_index,
          source_identifier: source_id,
          severity: 'warning',
          category: 'existing_source_identifier',
          column: source_id_label,
          value: source_id,
          message: I18n.t('bulkrax.importer.guided_import.validation.existing_source_identifier_validator.warnings.message',
                          value: source_id,
                          field: source_id_label),
          suggestion: I18n.t('bulkrax.importer.guided_import.validation.existing_source_identifier_validator.warnings.suggestion',
                             field: source_id_label)
        }
      end
      private_class_method :add_existing_warning
    end
  end
end
