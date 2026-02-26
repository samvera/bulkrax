# frozen_string_literal: true

module Bulkrax
  class CsvValidationService::RowValidatorService
    attr_reader :csv_data, :manager_mapper

    def initialize(csv_data, field_metadata = nil, manager_mapper = nil)
      @csv_data = csv_data
      @field_metadata = field_metadata
      @manager_mapper = manager_mapper
    end

    def valid?
      errors.none?
    end

    def errors?
      errors.any?
    end

    def errors
      @errors ||= validate
    end

    private

    def validate
      errors = []
      errors += duplicate_identifier_validator.validate
      errors += invalid_relationship_validator.validate
      errors += required_values_validator.validate
      errors += controlled_vocabulary_validator.validate
      errors
    end

    def duplicate_identifier_validator
      @duplicate_identifier_validator ||= DuplicateIdentifierValidator.new(csv_data, manager_mapper)
    end

    def invalid_relationship_validator
      @invalid_relationship_validator ||= InvalidRelationshipValidator.new(csv_data)
    end

    def required_values_validator
      @required_values_validator ||= RequiredValuesValidator.new(csv_data, @field_metadata)
    end

    def controlled_vocabulary_validator
      @controlled_vocabulary_validator ||= ControlledVocabularyValidator.new(csv_data, @field_metadata)
    end
  end
end
