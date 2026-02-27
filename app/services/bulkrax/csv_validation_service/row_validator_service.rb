# frozen_string_literal: true

module Bulkrax
  class CsvValidationService::RowValidatorService
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
      @errors ||= @processor_chain.flat_map { |method_name| send(method_name) }
    end

    def validate_duplicate_identifiers
      DuplicateIdentifierValidator.new(csv_data, manager_mapper).validate
    end

    def validate_parent_references
      InvalidRelationshipValidator.new(csv_data).validate
    end

    def validate_required_values
      RequiredValuesValidator.new(csv_data, field_metadata).validate
    end

    def validate_controlled_vocabulary
      ControlledVocabularyValidator.new(csv_data, field_metadata).validate
    end
  end
end
