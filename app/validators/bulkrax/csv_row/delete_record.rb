# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Tells which record a delete row removes, and blocks a delete row that
    # matches none, since the import fails it ("Object not found to delete").
    # A record of another model or an id naming no record is already
    # reported by DuplicateIdentifier; a lookup that failed is not a miss.
    module DeleteRecord
      def self.call(record, row_index, context)
        return unless record[:deleting]

        match = context[:find_existing_record]&.call(record)
        return if match && (match[:existing_model] || match[:missing] || match[:lookup_failed])

        field = match&.dig(:field) || context[:source_identifier] || 'source_identifier'
        value = match ? match[:value] : record[:source_identifier]
        severity, category, key = if match
                                    %w[warning delete_record warnings]
                                  else
                                    %w[error delete_record_not_found errors]
                                  end
        scope = "bulkrax.importer.guided_import.validation.delete_record_validator.#{key}"
        context[:errors] << {
          row: row_index,
          source_identifier: record[:source_identifier],
          severity: severity,
          category: category,
          column: field,
          value: value,
          message: I18n.t("#{scope}.message", value: value, field: field),
          suggestion: I18n.t("#{scope}.suggestion", value: value, field: field)
        }
      end
    end
  end
end
