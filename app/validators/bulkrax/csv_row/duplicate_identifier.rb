# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Validates that each row has a unique source_identifier.
    # Uses context[:seen_ids] (Hash: id => first_seen_row_number) to detect duplicates.
    module DuplicateIdentifier
      def self.call(record, row_index, context)
        source_id = record[:source_identifier]
        source_id_label = context[:source_identifier] || 'source_identifier'
        if source_id.blank? && Bulkrax.fill_in_blank_source_identifiers.present?
          add_existing_warning(record, context, row_index, source_id, source_id_label)
          return
        end

        first_row = context[:seen_ids][source_id]
        if first_row
          add_duplicate_error(context, row_index, source_id, source_id_label, first_row)
        else
          context[:seen_ids][source_id] = row_index
          add_existing_warning(record, context, row_index, source_id, source_id_label)
        end
      end

      def self.add_duplicate_error(context, row_index, source_id, source_id_label, first_row)
        context[:errors] << {
          row: row_index,
          source_identifier: source_id,
          severity: 'error',
          category: 'duplicate_source_identifier',
          column: source_id_label,
          value: source_id,
          message: I18n.t('bulkrax.importer.guided_import.validation.duplicate_identifier_validator.errors.message',
                          value: source_id,
                          field: source_id_label,
                          original_row: first_row),
          suggestion: I18n.t('bulkrax.importer.guided_import.validation.duplicate_identifier_validator.errors.suggestion',
                             field: source_id_label)
        }
      end
      private_class_method :add_duplicate_error

      def self.add_existing_warning(record, context, row_index, source_id, source_id_label)
        match = context[:find_existing_record]&.call(record)
        return if match.nil? || match[:lookup_failed]

        field = match[:field] || source_id_label
        issue = if match[:existing_model]
                  ['error', 'existing_record_model_mismatch', 'existing_record_model_mismatch_validator.errors']
                elsif match[:missing]
                  ['error', 'existing_record_id_not_found', 'existing_record_id_not_found_validator.errors']
                elsif record[:deleting]
                  nil
                elsif record[:rerunning]
                  ['warning', 'remove_and_rerun_record', 'remove_and_rerun_validator.warnings']
                else
                  ['warning', 'existing_source_identifier', 'existing_source_identifier_validator.warnings']
                end
        return unless issue

        add_existing_issue(context, row_index, source_id, field, match, *issue)
      end

      def self.add_existing_issue(context, row_index, source_id, field, match, severity, category, key) # rubocop:disable Metrics/ParameterLists
        scope = "bulkrax.importer.guided_import.validation.#{key}"
        values = { value: match[:value], field: field, existing_model: match[:existing_model], model: match[:model] }
        suggestion = match[:existing_model] && match[:field] ? 'id_suggestion' : 'suggestion'
        context[:errors] << {
          row: row_index,
          source_identifier: source_id,
          severity: severity,
          category: category,
          column: field,
          value: match[:value],
          message: I18n.t("#{scope}.message", **values),
          suggestion: I18n.t("#{scope}.#{suggestion}", **values)
        }
      end
      private_class_method :add_existing_issue

      private_class_method :add_existing_warning
    end
  end
end
