# frozen_string_literal: true

module Bulkrax
  # Main service class that orchestrates CSV generation
  class SampleCsvService
    attr_reader :model_name, :mappings, :all_models

    def initialize(model_name: nil)
      @model_name = model_name
      @mapping_manager = MappingManager.new
      @mappings = @mapping_manager.mappings
      @all_models = ModelLoader.new(model_name).models
      @field_analyzer = FieldAnalyzer.new(@mappings)
      @csv_builder = CsvBuilder.new(self)
    end

    def self.call(model_name: nil, output: 'file', **args)
      raise NameError, "Hyrax is not defined" unless defined?(::Hyrax)
      new(model_name: model_name).send("to_#{output}", **args)
    end

    def to_file(file_path: nil)
      file_path ||= FilePathGenerator.default_path
      @csv_builder.write_to_file(file_path)
      file_path
    end

    def to_csv_string
      @csv_builder.generate_string
    end

    # Delegate methods to appropriate components
    attr_reader :field_analyzer

    attr_reader :mapping_manager
  end
end
