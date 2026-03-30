# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Validates that any child references in a row point to source identifiers
    # that exist elsewhere in the same CSV.
    # Uses context[:all_ids] (Set of all source identifiers) to validate references.
    # Skips validation when all_ids is empty and fill_in_blank_source_identifiers is
    # configured, since generated identifiers cannot be cross-referenced at validation time.
    module ChildReference
      def self.call(record, row_index, context)
        children = record[:children]
        return if children.blank?

        all_ids = context[:all_ids]
        return if all_ids.empty? && Bulkrax.fill_in_blank_source_identifiers.present?

        child_ids = children.to_s.split('|').map(&:strip).reject(&:blank?)

        child_ids.each do |child_id|
          next if all_ids.include?(child_id)

          context[:errors] << {
            row: row_index,
            source_identifier: record[:source_identifier],
            severity: 'error',
            category: 'invalid_child_reference',
            column: 'children',
            value: child_id,
            message: I18n.t('bulkrax.importer.guided_import.validation.child_reference_validator.errors.message',
                            value: child_id,
                            field: 'source_identifier'),
            suggestion: I18n.t('bulkrax.importer.guided_import.validation.child_reference_validator.errors.suggestion')
          }
        end
      end
    end
  end
end
