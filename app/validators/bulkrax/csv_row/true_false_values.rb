# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Reports a true/false cell that is neither true nor false (Bulkrax::TrueFalse):
    # a flag column, whose action import then skips, or a true/false property of the
    # row's model, whose import fails.
    module TrueFalseValues
      def self.call(record, row_index, context)
        cells(record, context).each do |column, value|
          next if value.nil? || !Bulkrax::TrueFalse.cast(value).nil?

          scope = 'bulkrax.importer.guided_import.validation.true_false_validator.errors'
          context[:errors] << {
            row: row_index,
            source_identifier: record[:source_identifier],
            severity: 'error',
            category: 'invalid_true_false',
            column: column,
            value: value,
            message: I18n.t("#{scope}.message", value: value, field: column),
            suggestion: I18n.t("#{scope}.suggestion")
          }
        end
      end

      def self.cells(record, context)
        raw_row = record[:raw_row] || {}
        flags = %w[delete remove_and_rerun].map { |column| [column, raw_row[column]] }
        return flags if record[:deleting]

        model = record[:model].presence || Bulkrax.default_work_type
        properties = context[:field_metadata]&.dig(model, :true_false_terms) || []
        flags + properties.filter_map { |field| Bulkrax::FieldResolver.row_value(raw_row, context[:mappings], field) }
      end
      private_class_method :cells
    end
  end
end
