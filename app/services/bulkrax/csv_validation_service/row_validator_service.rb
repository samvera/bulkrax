# frozen_string_literal: true

module Bulkrax
  class CsvValidationService::RowValidatorService
    include CsvValidationService::RowValidatorService::ValidatorHelpers

    class_attribute :default_processor_chain
    self.default_processor_chain = [
      :validate_duplicate_identifiers,
      :validate_parent_references,
      :validate_required_values,
      :validate_controlled_vocabulary
    ]

    attr_reader :csv_data, :field_metadata, :manager_mapper

    def initialize(csv_data, field_metadata = nil, manager_mapper = nil)
      @csv_data = csv_data
      @field_metadata = field_metadata
      @manager_mapper = manager_mapper
      @processor_chain = default_processor_chain.dup
    end

    def valid?
      errors.none?
    end

    def errors?
      errors.any?
    end

    def errors
      @errors ||= [].tap do |errors|
        @processor_chain.each { |method_name| send(method_name, errors) }
      end
    end

    def validate_duplicate_identifiers(errors)
      DuplicateIdentifierValidator.new(csv_data, manager_mapper).validate(errors)
    end

    def validate_parent_references(errors)
      InvalidRelationshipValidator.new(csv_data, manager_mapper).validate(errors)
    end

    def validate_required_values(errors)
      RequiredValuesValidator.new(csv_data, field_metadata).validate(errors)
    end

    def validate_controlled_vocabulary(errors)
      ControlledVocabularyValidator.new(csv_data, field_metadata).validate(errors)
    end
  end
end
