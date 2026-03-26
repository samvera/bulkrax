# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Validates that controlled vocabulary values in each row are valid according to the
    # QA authority for that field.
    module ControlledVocabulary
      def self.call(record, row_index, context) # rubocop:disable Metrics/MethodLength
        field_metadata = context[:field_metadata]
        return if field_metadata.blank?

        model = record[:model]
        metadata = field_metadata[model]
        return if metadata.blank?

        controlled_terms = metadata[:controlled_vocab_terms] || []
        return if controlled_terms.blank?

        controlled_terms.each do |field|
          value = record[:raw_row][field]
          next if value.blank?

          authority = load_authority(field)
          next if authority.nil?

          term = authority.find(value)
          next unless term.blank? || term.dig('active') == false

          context[:errors] << {
            row: row_index,
            source_identifier: record[:source_identifier],
            severity: 'error',
            category: 'invalid_controlled_value',
            column: field,
            value: value,
            message: I18n.t('bulkrax.importer.guided_import.validation.controlled_vocabulary_validator.errors.message',
                            value: value, field: field),
            suggestion: suggestion(value, authority)
          }
        end
      end

      def self.load_authority(field)
        Qa::Authorities::Local.subauthority_for(field.pluralize)
      rescue Qa::InvalidSubAuthority
        begin
          Qa::Authorities::Local.subauthority_for(field)
        rescue Qa::InvalidSubAuthority
          nil
        end
      end
      private_class_method :load_authority

      def self.suggestion(value, authority)
        suggestion = DidYouMean::SpellChecker.new(dictionary: dictionary_for(authority)).correct(value).first
        return fallback_suggestion if suggestion.nil?

        I18n.t('bulkrax.importer.guided_import.validation.did_you_mean', suggestion: suggestion)
      end
      private_class_method :suggestion

      def self.fallback_suggestion
        I18n.t('bulkrax.importer.guided_import.validation.controlled_vocabulary_validator.errors.suggestion')
      end
      private_class_method :fallback_suggestion

      def self.dictionary_for(authority)
        authority.all.filter_map { |term| term['label'] if term['active'] == true }.uniq
      end
      private_class_method :dictionary_for
    end
  end
end
