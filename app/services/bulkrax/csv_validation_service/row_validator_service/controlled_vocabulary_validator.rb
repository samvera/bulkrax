# frozen_string_literal: true

module Bulkrax
  class CsvValidationService::RowValidatorService::ControlledVocabularyValidator
    attr_reader :csv_data, :field_metadata

    def initialize(csv_data, field_metadata)
      @csv_data = csv_data
      @field_metadata = field_metadata
    end

    # rubocop:disable Metrics/MethodLength
    def validate
      return [] if @field_metadata.blank?

      errors = []

      csv_data.each_with_index do |row, index|
        model = row[:model]
        metadata = @field_metadata[model]
        next if metadata.blank?

        controlled_terms = metadata[:controlled_vocab_terms] || []
        next if controlled_terms.blank?

        controlled_terms.each do |field|
          value = row[:raw_row][field]
          next if value.blank?

          authority = load_authority(field)
          next if authority.nil?

          term = authority.find(value)
          term_invalid = term.blank? || term.dig('active') == false
          next unless term_invalid

          errors << {
            row: index + 2, # index starts at 0 which is the first row, adding 2 to account for header row and 0-based index
            source_identifier: row[:source_identifier],
            severity: 'error',
            category: 'invalid_controlled_value',
            column: field,
            value: value,
            message: [I18n.t('bulkrax.importer.guided_import.validation.controlled_vocabulary_validator.errors.message', value: value, field: field), suggestion(value, authority)].join(' '),
            suggestion: suggestion(value, authority)
          }
        end
      end

      errors
    end
    # rubocop:enable Metrics/MethodLength

    private

    def load_authority(field)
      Qa::Authorities::Local.subauthority_for(field.pluralize)
    rescue Qa::InvalidSubAuthority
      Qa::Authorities::Local.subauthority_for(field)
    rescue Qa::InvalidSubAuthority
      nil
    end

    def suggestion(value, authority)
      suggestion = DidYouMean::SpellChecker.new(dictionary: dictionary_for(authority)).correct(value).first
      return fallback_suggestion if suggestion.nil?

      I18n.t('bulkrax.importer.guided_import.validation.did_you_mean', suggestion: suggestion)
    end

    def fallback_suggestion
      I18n.t('bulkrax.importer.guided_import.validation.controlled_vocabulary_validator.errors.suggestion')
    end

    def dictionary_for(authority)
      authority.all.filter_map { |term| term['label'] if term['active'] == true }.uniq
    end
  end
end
