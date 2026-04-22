# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Validates that any child references in a row point to source identifiers
    # that exist either elsewhere in the same CSV or as existing repository records.
    # Uses context[:all_ids] (Set of all source identifiers) to validate references
    # within the CSV, and context[:find_record_by_source_identifier] (callable) to
    # look up existing records in the same way the importer does at runtime.
    # Skips validation when all_ids is empty and fill_in_blank_source_identifiers is
    # configured, since generated identifiers cannot be cross-referenced at validation time.
    module ChildReference
      def self.call(record, row_index, context)
        all_ids = context[:all_ids]
        return if all_ids.empty? && Bulkrax.fill_in_blank_source_identifiers.present?

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
        split_pattern = Bulkrax::SplitPatternCoercion.coerce(context[:child_split_pattern]) ||
                        Bulkrax::DEFAULT_MULTI_VALUE_ELEMENT_SPLIT_ON
        children_column = context[:children_column] || 'children'

        base_ids = record[:children].to_s.split(split_pattern).map(&:strip).reject(&:blank?)

        suffix_pattern = /\A#{Regexp.escape(children_column)}_\d+\z/
        suffix_ids = record[:raw_row]
                     .select { |k, _| k.to_s.match?(suffix_pattern) }
                     .values
                     .map(&:to_s).map(&:strip).reject(&:blank?)

        (base_ids + suffix_ids).uniq
      end
      private_class_method :collect_child_ids
    end
  end
end
