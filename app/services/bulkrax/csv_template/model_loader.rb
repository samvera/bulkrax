# frozen_string_literal: true

module Bulkrax
  module CsvTemplate
    # Handles model loading based on configuration
    class ModelLoader
      extend Deprecation
      attr_reader :models

      def initialize(models)
        @models = load_models(models)
      end

      def self.determine_klass_for(model_name)
        Deprecation.warn(self, 'determine_klass_for is deprecated and will be removed in Bulkrax 11.0. Use Bulkrax::FactoryClassFinder.resolve instead.')
        FactoryClassFinder.resolve(model_name)
      end

      private

      def load_models(models)
        case models
        when Array
          return all_available_models if models.empty?
          return all_available_models if models.include?('all')
          models.select { |model| FactoryClassFinder.resolve(model) }
        else
          all_available_models
        end
      end

      def all_available_models
        Hyrax.config.curation_concerns.map(&:name) +
          [Bulkrax.collection_model_class&.name, Bulkrax.file_model_class&.name].compact
      end
    end
  end
end
