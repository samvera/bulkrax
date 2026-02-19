# frozen_string_literal: true

module Bulkrax
  # Analyzes model fields and schemas
  class CsvValidationService::FieldAnalyzer
    attr_reader :field_list

    def initialize(mappings, admin_set_id = nil)
      @mappings = mappings
      @field_list = []
      @schema = nil
      @admin_set_id = admin_set_id
    end

    def find_or_create_field_list_for(model_name:)
      existing = @field_list.find { |entry| entry.key?(model_name) }
      return existing if existing.present?

      klass = CsvValidationService::ModelLoader.determine_klass_for(model_name)
      return {} if klass.nil?

      model_entry = build_field_list_entry(model_name, klass)
      @field_list << model_entry
      model_entry
    end

    def controlled_vocab_terms
      @field_list.flat_map do |hash|
        hash.values.flat_map { |data| data["controlled_vocab_terms"] || [] }
      end.uniq
    end

    private

    def build_field_list_entry(model_name, klass)
      schema_analyzer = CsvValidationService::SchemaAnalyzer.new(klass: klass, admin_set_id: @admin_set_id)
      {
        model_name => {
          'properties' => extract_properties(klass),
          'required_terms' => schema_analyzer.required_terms,
          'controlled_vocab_terms' => schema_analyzer.controlled_vocab_terms
        }
      }
    end

    def extract_properties(klass)
      if klass.respond_to?(:schema)
        Bulkrax::ValkyrieObjectFactory.schema_properties(klass: klass, admin_set_id: @admin_set_id).map(&:to_s)
      else
        klass.properties.keys.map(&:to_s)
      end
    end
  end
end
