# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Validates that any parent references in a row point to source identifiers
    # that exist either elsewhere in the same CSV or as existing repository records.
    # Uses context[:all_ids] (Set of all source identifiers) to validate references
    # within the CSV, and context[:find_record_by_source_identifier] (callable) to
    # look up existing records in the same way the importer does at runtime.
    # Uses context[:parent_split_pattern] (String/Regexp, may be nil) for multi-value splitting.
    module ParentReference
      def self.call(record, row_index, context)
        all_ids = context[:all_ids]
        find_record = context[:find_record_by_source_identifier]

        collect_parent_ids(record, context).each do |parent_id|
          next if all_ids.include?(parent_id)
          next if find_record&.call(parent_id)

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

      def self.collect_parent_ids(record, context)
        split_pattern = Bulkrax::SplitPatternCoercion.coerce(context[:parent_split_pattern])
        parent_column = context[:parent_column] || 'parents'

        base_ids = if split_pattern
                     record[:parent].to_s.split(split_pattern).map(&:strip).reject(&:blank?)
                   elsif record[:parent].present?
                     [record[:parent].to_s.strip]
                   else
                     []
                   end

        suffix_pattern = /\A#{Regexp.escape(parent_column)}_\d+\z/
        suffix_ids = record[:raw_row]
                     .select { |k, _| k.to_s.match?(suffix_pattern) }
                     .values
                     .map(&:to_s).map(&:strip).reject(&:blank?)

        (base_ids + suffix_ids).uniq
      end
      private_class_method :collect_parent_ids
    end
  end
end
