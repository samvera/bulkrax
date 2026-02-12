# frozen_string_literal: true

module Bulkrax
  # Handles model loading based on configuration
  class SampleCsvService::ModelLoader
    attr_reader :models

    def initialize(models)
      @models = load_models(models)
    end

    def self.determine_klass_for(model_name)
      if Bulkrax.config.object_factory == Bulkrax::ValkyrieObjectFactory
        Valkyrie.config.resource_class_resolver.call(model_name)
      else
        model_name.constantize
      end
    rescue StandardError
      nil
    end

    private

    def load_models(models)
      case models
      when Array
        return all_available_models if models.empty?
        return all_available_models if models.include?('all')
        models.map { |model| model.constantize ? model : nil }.compact
      else
        all_available_models
      end
    rescue StandardError
      []
    end

    def all_available_models
      Hyrax.config.curation_concerns.map(&:name) +
        [Bulkrax.collection_model_class&.name, Bulkrax.file_model_class&.name].compact
    end
  end
end
