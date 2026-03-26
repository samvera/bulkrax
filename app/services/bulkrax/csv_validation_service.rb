# frozen_string_literal: true

module Bulkrax
  ## Unified service class for CSV template generation and validation
  #  See CSV_SERVICE_ARCHITECTURE.md for detailed architecture and design documentation.
  #
  ## Purpose:
  # Provides comprehensive CSV operations for Bulkrax imports:
  # 1. Template Generation - Creates sample CSV files showing valid structure and fields
  # 2. CSV Validation - Validates uploaded CSV files against model schemas (delegates to CsvParser)
  # 3. Schema Analysis - Provides metadata about valid fields, required fields, and controlled vocabularies
  #
  ## Architecture Components:
  #
  # 1. Initialization & Setup
  #    - Loads Bulkrax field mappings (excluding auto-generated fields) via MappingManager
  #    - Generation mode only: supply `models:` argument
  #    - Supports both ActiveFedora and Valkyrie object factories
  #
  # 2. Field Analysis (via FieldAnalyzer & SchemaAnalyzer)
  #    - Examines each model's schema to extract all available properties
  #    - Identifies required fields, controlled vocabulary terms, and multi-value fields
  #    - Introspects model schemas differently based on Valkyrie vs ActiveFedora
  #
  # 3. Column Building (via ColumnBuilder)
  #    - Assembles complete list of valid CSV columns by combining:
  #      * Bulkrax-specific fields (model, source_identifier, parent, etc.)
  #      * Model properties mapped through the field mapping system
  #      * Controlled vocabulary information
  #    - Filters out internal/system properties (created_at, updated_at, file_ids, embargo_id, etc.)
  #
  # 4. Template Generation (via CsvBuilder, RowBuilder, ExplanationBuilder)
  #    - Header Row: Column names mapped through Bulkrax's field mappings
  #    - Explanation Row: Descriptions of what each column expects
  #    - Data Rows: One row per model showing appropriate sample values
  #    - Intelligently removes empty columns to keep templates clean
  #
  # 5. CSV Validation — delegated to CsvParser.validate_csv
  #    - Row validators are registered on CsvParser via register_csv_row_validator
  #    - The validate class method is a thin facade over CsvParser.validate_csv
  #
  ## Sample Usage:
  #
  # Template Generation:
  #   Bulkrax::CsvValidationService.generate_template(models: ['GenericWork'], output: 'file')
  #   Bulkrax::CsvValidationService.generate_template(models: 'all', output: 'csv_string')
  #
  # CSV Validation:
  #   result = Bulkrax::CsvValidationService.validate(csv_file: csv_file, zip_file: zip_file)
  #   # Returns hash with: headers, missingRequired, unrecognized, rowCount, isValid, etc.
  #
  class CsvValidationService
    attr_reader :mappings, :all_models, :admin_set_id

    # ============================================================================
    # CLASS METHODS - Primary entry points
    # ============================================================================

    # Generate a CSV template for the specified models
    #
    # @param models [Array<String>, String] Model names or 'all' for all available models
    # @param output [String] Output format: 'file' or 'csv_string'
    # @param args [Hash] Additional arguments passed to output method (e.g., file_path)
    # @param admin_set_id [String, nil] Optional admin set ID for context
    # @return [String] File path (for 'file' output) or CSV string (for 'csv_string' output)
    def self.generate_template(models: [], output: 'file', admin_set_id: nil, **args)
      raise NameError, "Hyrax is not defined" unless defined?(::Hyrax)
      new(models: models, admin_set_id: admin_set_id).send("to_#{output}", **args)
    end

    # Validate a CSV file and optional zip archive.
    # Delegates to CsvParser.validate_csv.
    #
    # @param csv_file [File, ActionDispatch::Http::UploadedFile] CSV file to validate
    # @param zip_file [File, ActionDispatch::Http::UploadedFile, nil] Optional zip archive
    # @param admin_set_id [String, nil] Optional admin set ID for context
    # @return [Hash] Validation result hash (same shape as before)
    def self.validate(csv_file: nil, zip_file: nil, admin_set_id: nil)
      CsvParser.validate_csv(csv_file: csv_file, zip_file: zip_file, admin_set_id: admin_set_id)
    end

    # ============================================================================
    # INITIALIZATION (generation mode only)
    # ============================================================================

    def initialize(models: nil, admin_set_id: nil)
      @admin_set_id = admin_set_id

      @mapping_manager = CsvValidationService::MappingManager.new
      @mappings = @mapping_manager.mappings
      @field_analyzer = CsvValidationService::FieldAnalyzer.new(@mappings, admin_set_id)
      @all_models = CsvValidationService::ModelLoader.new(Array.wrap(models)).models
      @csv_builder = CsvValidationService::CsvBuilder.new(self)
    end

    # ============================================================================
    # TEMPLATE GENERATION METHODS
    # ============================================================================

    # Generate template as a file
    #
    # @param file_path [String, nil] Path to write file (uses default if nil)
    # @return [String] Path to written file
    def to_file(file_path: nil)
      file_path ||= CsvValidationService::FilePathGenerator.default_path(@admin_set_id)
      @csv_builder.write_to_file(file_path)
      file_path
    end

    # Generate template as a CSV string
    #
    # @return [String] CSV content as string
    # Note: This method is primarily for testing
    def to_csv_string
      @csv_builder.generate_string
    end

    # ============================================================================
    # SHARED ANALYSIS METHODS
    # ============================================================================

    # Get comprehensive field metadata for all models in the template
    #
    # @return [Hash] Hash mapping model names to their field metadata:
    #   - properties: Array of all property names
    #   - required_terms: Array of required field names
    #   - controlled_vocab_terms: Array of controlled vocabulary field names
    def field_metadata_for_all_models
      @field_metadata ||= @all_models.each_with_object({}) do |model, hash|
        field_list = @field_analyzer.find_or_create_field_list_for(model_name: model)
        hash[model] = {
          properties: field_list.dig(model, "properties") || [],
          required_terms: field_list.dig(model, "required_terms") || [],
          controlled_vocab_terms: field_list.dig(model, "controlled_vocab_terms") || []
        }
      end
    end

    # Get all valid column names for the models
    #
    # @return [Array<String>] Array of valid column names
    def valid_headers_for_models
      @valid_headers ||= begin
        column_builder = CsvValidationService::ColumnBuilder.new(self)
        all_columns = column_builder.all_columns
        all_columns - CsvValidationService::CsvBuilder::IGNORED_PROPERTIES
                         rescue StandardError => e
                           Rails.logger.error("Error building valid headers: #{e.message}")
                           standard_fields = %w[model source_identifier parent parents file]
                           model_fields = field_metadata_for_all_models.values.flat_map { |m| m[:properties] }
                           (standard_fields + model_fields).uniq
      end
    end

    # Delegate to components
    attr_reader :field_analyzer, :mapping_manager
  end
end
