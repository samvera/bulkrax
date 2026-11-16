# frozen_string_literal: true

module Bulkrax
  module CsvRow
    # Reads a row's parent or child ids the way import does: from every column
    # that feeds the relationship field (each `from:` alias and the mapping key)
    # and their numbered forms (`parents_1`, `parents_2`), splitting each cell.
    module RelationshipIds
      def self.columns(mappings, flag, default)
        key = Bulkrax::FieldResolver.flagged_key(mappings, flag)
        Bulkrax::FieldResolver.headers_for_field(mappings, key || default)
      end

      # `base_value` is the row's already-resolved relationship cell, kept so
      # callers that build records without a matching raw_row column still work.
      def self.ids(base_value, raw_row, columns, split_pattern)
        pattern = Bulkrax::SplitPatternCoercion.coerce(split_pattern)
        cells = [base_value] + (raw_row || {}).select { |header, _| Bulkrax::FieldResolver.header_for_any?(header, columns) }.values

        cells.flat_map { |cell| pattern ? cell.to_s.split(pattern) : [cell.to_s] }
             .map(&:strip).reject(&:blank?).uniq
      end

      # A relationship to a row this import deletes: import writes no pending
      # relationship for it (ImportBehavior#parent_jobs), so it is never made.
      def self.deleted_reference_error(record, row_index, column, value)
        scope = 'bulkrax.importer.guided_import.validation.deleted_record_reference_validator.errors'
        {
          row: row_index,
          source_identifier: record[:source_identifier],
          severity: 'error',
          category: 'deleted_record_reference',
          column: column,
          value: value,
          message: I18n.t("#{scope}.message", value: value),
          suggestion: I18n.t("#{scope}.suggestion", value: value, field: column)
        }
      end
    end
  end
end
