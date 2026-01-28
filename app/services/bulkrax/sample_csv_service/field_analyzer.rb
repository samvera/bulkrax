# frozen_string_literal: true

module Bulkrax
  # Analyzes model fields and schemas
  class SampleCsvService::FieldAnalyzer
    attr_reader :field_list

    def initialize(mappings)
      @mappings = mappings
      @field_list = []
      @schema = nil
    end

    def find_or_create_field_list_for(model_name:)
      existing = @field_list.find { |entry| entry.key?(model_name) }
      return existing if existing.present?

      klass = SampleCsvService::ModelLoader.determine_klass_for(model_name)
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
      schema_analyzer = SampleCsvService::SchemaAnalyzer.new(klass)

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
        Bulkrax::ValkyrieObjectFactory.schema_properties(klass).map(&:to_s)
      else
        klass.properties.keys.map(&:to_s)
      end
    end
  end
end
