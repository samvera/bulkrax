# frozen_string_literal: true

module Bulkrax
  # Analyzes model schemas for required and controlled vocabulary fields
  class CsvValidationService::SchemaAnalyzer
    def initialize(klass, admin_set_id = nil)
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
      # Yes, this looks strange. The fallback is intentional.
      # At the point in time when this service is being created, Hyrax behaves
      # differently between flexible metadata setting on & off. This may be modified
      # in the future, and this code can be revisited then.
      # flexible=true: @klass.new.singleton_class.schema would return the full schema,
      #                but @klass.schema doesn't get the flexible metadata terms
      # flexible=false: @klass.new.singleton_class.schema returns nil so it will fallback
      #
      # When the admin set has contexts defined, pass them so that context-restricted
      # fields (e.g. M3 `available_on.context`) appear in required_terms and
      # controlled_vocab_terms for that admin set. Only pass contexts when the model
      # supports flexible metadata (HYRAX_FLEXIBLE=true); non-flexible models do not
      # accept :contexts and would raise.
      contexts = Bulkrax::ValkyrieObjectFactory.contexts_for_admin_set(@admin_set_id)
      use_contexts = Bulkrax::ValkyrieObjectFactory.use_contexts?(contexts, @klass)
      instance = use_contexts ? @klass.new(contexts: contexts) : @klass.new
      instance.singleton_class.schema || @klass.schema
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
