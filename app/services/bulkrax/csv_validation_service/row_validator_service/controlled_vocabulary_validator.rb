# frozen_string_literal: true

module Bulkrax
  class CsvValidationService::RowValidatorService::ControlledVocabularyValidator
    include Bulkrax::CsvValidationService::RowValidatorService::ValidatorHelpers

    attr_reader :csv_data, :field_metadata

    def initialize(csv_data, field_metadata)
      @csv_data = csv_data
      @field_metadata = field_metadata
    end

    # rubocop:disable Metrics/MethodLength
    def validate(errors)
      return if @field_metadata.blank?

      each_row do |row, row_number|
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
          next unless term.blank? || term.dig('active') == false

          errors << {
            row: row_number,
            source_identifier: row[:source_identifier],
            severity: 'error',
            category: 'invalid_controlled_value',
            column: field,
            value: value,
            message: I18n.t('bulkrax.importer.guided_import.validation.controlled_vocabulary_validator.errors.message', value: value, field: field),
            suggestion: suggestion(value, authority)
          }
        end
      end
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
