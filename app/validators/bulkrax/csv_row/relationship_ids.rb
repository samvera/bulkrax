# frozen_string_literal: true

module Bulkrax
  module CsvRow
    # Reads a row's parent or child ids the way import does: from every column
    # that feeds the relationship field (each `from:` alias and the mapping key)
    # and their numbered forms (`parents_1`, `parents_2`), splitting each cell.
    module RelationshipIds
      def self.columns(mappings, flag, default)
        key, = (mappings || {}).find { |_k, v| v.is_a?(Hash) && (v[flag] || v[flag.to_sym]) }
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
    end
  end
end
