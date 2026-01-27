# frozen_string_literal: true

module Bulkrax
  ## Main service class that orchestrates CSV generation
  #
  ## Purpose:
  # Generates CSV import templates that help users understand what fields are available for bulk importing content into a Hyrax repository.
  # The service uses a modular architecture with specialized components that work together to create intelligent, model-specific CSV templates:

  ## 1. Initialization & Setup
  # Loads Bulkrax field mappings (excluding auto-generated fields) via MappingManager
  # Determines which models to include via ModelLoader (can target a specific model, all models, or none)
  # Supports both ActiveFedora and Valkyrie object factories

  ## 2. Field Analysis
  # FieldAnalyzer examines each model's schema to extract all available properties, and identifies:
  # Required fields
  # Controlled vocabulary terms
  # If a term column can be split into multiple values during import
  # SchemaAnalyzer introspects model schemas differently based on whether they're Valkyrie or ActiveFedora models

  ## 3. Column Building
  # ColumnBuilder assembles the complete list of valid CSV columns by combining:
  # Bulkrax-specific fields (model, source_identifier, parent, etc.)
  # Model properties mapped through the field mapping system
  # Controlled vocabulary information
  # Filters out internal/system properties (created_at, updated_at, file_ids, embargo_id, etc.)

  ## 4. Row Generation
  # The service creates three types of rows:
  # Header Row: Column names mapped through Bulkrax's field mappings
  # Explanation Row: Descriptions of what each column expects (via ExplanationBuilder and ColumnDescriptor)
  # Data Rows: One row per model showing appropriate sample values (via RowBuilder and ValueDeterminer)

  ## 5. Intelligent Filtering
  # Removes completely empty columns to keep the template clean and focused
  # Preserves columns that contain any data across any model row

  # 6. Output
  # Can generate either a CSV file (default location: tmp/sample_csv_import_template.csv) or a CSV string
  # Uses Ruby's CSV library for proper formatting and escaping

  ## Sample Usage:
  #   Bulkrax::SampleCsvService.call(model_name: 'GenericWork', output: 'file', file_path: 'path/to/output.csv')
  #   Bulkrax::SampleCsvService.call(model_name: nil, output: 'csv_string')
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
