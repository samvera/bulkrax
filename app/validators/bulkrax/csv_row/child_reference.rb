# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Validates that any child references in a row point to source identifiers
    # that exist either elsewhere in the same CSV or as existing repository records.
    # Uses context[:all_ids] (Set of all source identifiers) to validate references
    # within the CSV, and context[:find_record_by_source_identifier] (callable) to
    # look up existing records in the same way the importer does at runtime.
    module ChildReference
      def self.call(record, row_index, context)
        all_ids = context[:all_ids]
        find_record = context[:find_record_by_source_identifier]

        collect_child_ids(record, context).each do |child_id|
          next if all_ids.include?(child_id)
          next if find_record&.call(child_id)

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

      def self.collect_child_ids(record, context)
        split_pattern = Bulkrax::SplitPatternCoercion.coerce(context[:child_split_pattern])
        columns = context[:children_columns] || [context[:children_column] || 'children']
        RelationshipIds.ids(record[:children], record[:raw_row], columns, split_pattern)
      end
      private_class_method :collect_child_ids
    end
  end
end
