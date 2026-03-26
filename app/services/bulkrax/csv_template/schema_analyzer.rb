# frozen_string_literal: true

module Bulkrax
  module CsvTemplate
    # Analyzes model schemas for required and controlled vocabulary fields
    class SchemaAnalyzer
      def initialize(klass:, admin_set_id: nil)
        @klass = klass
        @admin_set_id = admin_set_id
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
        # Delegate to Hyrax.schema_for when available so that context-gated
        # properties (e.g. M3 available_on.context) are included when the admin
        # set defines them. Falls back to direct singleton schema loading otherwise.
        if @admin_set_id.present? && defined?(Hyrax) && Hyrax.respond_to?(:schema_for)
          Hyrax.schema_for(klass: @klass, admin_set_id: @admin_set_id)
        else
          @klass.new.singleton_class.schema || @klass.schema
        end
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
end
