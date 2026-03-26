# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Validates that any parent references in a row point to source identifiers that exist
    # elsewhere in the same CSV.
    # Uses context[:all_ids] (Set of all source identifiers) to validate references.
    # Uses context[:parent_split_pattern] (String/Regexp, may be nil) for multi-value splitting.
    module ParentReference
      def self.call(record, row_index, context)
        parents = record[:parent]
        return if parents.blank?

        all_ids = context[:all_ids]
        split_pattern = context[:parent_split_pattern]

        parent_ids = if split_pattern
                       parents.to_s.split(split_pattern).map(&:strip).reject(&:blank?)
                     else
                       [parents.to_s.strip]
                     end

        parent_ids.each do |parent_id|
          next if all_ids.include?(parent_id)

          context[:errors] << {
            row: row_index,
            source_identifier: record[:source_identifier],
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
  end
end
