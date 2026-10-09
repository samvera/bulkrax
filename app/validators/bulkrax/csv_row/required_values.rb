# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Validates that each row provides a value for every required field of its model.
    # Numeric suffixes on column names are normalised before checking
    # (e.g. 'title_1' satisfies the 'title' requirement).
    module RequiredValues
      def self.call(record, row_index, context)
        field_metadata = context[:field_metadata]
        return if field_metadata.blank?

        using_default = record[:model].blank?
        model         = record[:model].presence || Bulkrax.default_work_type
        metadata      = field_metadata[model]
        return if metadata.blank?

        add_default_work_type_warning(context, record, row_index, model) if using_default
        add_missing_required_value_errors(context, record, row_index, metadata, context[:mapping_manager])
      end

      def self.add_default_work_type_warning(context, record, row_index, model)
        # Suppress per-row warning when a file-level notice already covers all rows.
        return if context[:notices]&.any? { |n| n[:field] == 'model' }

        context[:errors] << {
          row: row_index,
          source_identifier: record[:source_identifier],
          severity: 'warning',
          category: 'default_work_type_used',
          column: 'model',
          value: nil,
          message: I18n.t('bulkrax.importer.guided_import.validation.default_work_type_validator.warnings.message',
                          default_work_type: model),
          suggestion: I18n.t('bulkrax.importer.guided_import.validation.default_work_type_validator.warnings.suggestion')
        }
      end
      private_class_method :add_default_work_type_warning

      def self.add_missing_required_value_errors(context, record, row_index, metadata, mapping_manager)
        (metadata[:required_terms] || []).each do |field|
          column_present = record[:raw_row].keys.any? { |key| resolve_header(key.to_s, mapping_manager) == field }
          next unless column_present
          next if record[:raw_row].any? { |key, value| resolve_header(key.to_s, mapping_manager) == field && value.present? }

          context[:errors] << {
            row: row_index,
            source_identifier: record[:source_identifier],
            severity: 'error',
            category: 'missing_required_value',
            column: field,
            value: nil,
            message: I18n.t('bulkrax.importer.guided_import.validation.required_field_validator.errors.message', field: field),
            suggestion: I18n.t('bulkrax.importer.guided_import.validation.required_field_validator.errors.suggestion', field: field)
          }
        end
      end
      private_class_method :add_missing_required_value_errors

      # Resolves a raw CSV header into its mapping key so that `from:` aliases
      # are honoured (e.g. a column named `rights` satisfies the requirement
      # for `rights_statement` when the mapping declares
      # `rights_statement: { from: ['rights', 'rights_statement', ...] }`).
      # Numeric suffixes (e.g. `title_1`) are stripped before lookup so they
      # satisfy the unsuffixed required field.
      def self.resolve_header(header, mapping_manager)
        base = normalize_header(header)
        mapping_manager ? mapping_manager.mapped_to_key(base) : base
      end
      private_class_method :resolve_header

      def self.normalize_header(header)
        header.sub(/_\d+\z/, '')
      end
    end
  end
end
