# frozen_string_literal: true

module Bulkrax
  # Analyzes model schemas for required and controlled vocabulary fields
  class SampleCsvService::SchemaAnalyzer
    def initialize(klass)
      @klass = klass
      @schema = load_schema
    end

    def required_terms
      return [] if @schema.blank?

      @schema.select do |field|
        field.respond_to?(:meta) &&
          field.meta["form"].is_a?(Hash) &&
          field.meta["form"]["required"] == true
      end.map(&:name).map(&:to_s)
    rescue StandardError
      []
    end

    def controlled_vocab_terms
      return [] unless @schema

      controlled_properties = extract_controlled_properties
      controlled_properties.empty? ? registered_controlled_vocab_fields : controlled_properties
    rescue StandardError
      []
    end

    private

    def load_schema
      return nil unless @klass.respond_to?(:schema)
      @klass.new.singleton_class.schema || @klass.schema
    rescue StandardError
      nil
    end

    def extract_controlled_properties
      return [] unless @schema

      @schema.filter_map do |property|
        next unless property.respond_to?(:meta)
        sources = property.meta&.dig('controlled_values', 'sources')
        next if sources.nil? || sources == ['null'] || sources == 'null'
        property.name.to_s
      end
    end

    def registered_controlled_vocab_fields
      qa_registry.filter_map do |k, v|
        k.singularize if v.klass == Qa::Authorities::Local::FileBasedAuthority
      end
    end

    def qa_registry
      @qa_registry ||= Qa::Authorities::Local.registry.instance_variable_get('@hash')
    end
  end
end
