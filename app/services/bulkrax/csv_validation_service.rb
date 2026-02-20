# frozen_string_literal: true

module Bulkrax
  ## Unified service class for CSV template generation and validation
  #  See CSV_SERVICE_ARCHITECTURE.md for detailed architecture and design documentation.
  #
  ## Purpose:
  # Provides comprehensive CSV operations for Bulkrax imports:
  # 1. Template Generation - Creates sample CSV files showing valid structure and fields
  # 2. CSV Validation - Validates uploaded CSV files against model schemas
  # 3. Schema Analysis - Provides metadata about valid fields, required fields, and controlled vocabularies
  #
  # The service uses a modular architecture with specialized components that work together to create
  # intelligent, model-specific CSV templates and perform thorough validation.
  #
  ## Architecture Components:
  #
  # 1. Initialization & Setup
  #    - Loads Bulkrax field mappings (excluding auto-generated fields) via MappingManager
  #    - Two modes: Generation mode (models provided) or Validation mode (CSV file provided)
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
  # 5. CSV Validation (specialized subclasses)
  #    - CsvParser: Parses uploaded CSV to extract models and data
  #    - ColumnResolver: Resolves CSV column names from field mappings
  #    - Validator: Validates headers, checks required fields, identifies unrecognized columns
  #    - FileValidator: Validates file references against zip archive (if provided)
  #    - ItemExtractor: Provides hierarchical view of collections, works, and file sets
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
    attr_reader :mappings, :all_models

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

    # Validate a CSV file and optional zip archive
    #
    # @param csv_file [File, ActionDispatch::Http::UploadedFile] CSV file to validate
    # @param zip_file [File, ActionDispatch::Http::UploadedFile, nil] Optional zip archive with referenced files
    # @param admin_set_id [String, nil] Optional admin set ID for context
    def self.validate(csv_file: nil, zip_file: nil, admin_set_id: nil)
      new(csv_file: csv_file, zip_file: zip_file, admin_set_id: admin_set_id).validate
    end

    # ============================================================================
    # INITIALIZATION
    # ============================================================================

    # Initialize the service in either generation or validation mode
    #
    # @param models [Array<String>, String, nil] Models for template generation
    # @param csv_file [File, nil] CSV file for validation mode
    # @param zip_file [File, nil] Zip archive for validation mode
    # @param admin_set_id [String, nil] Optional admin set ID for context
    def initialize(models: nil, csv_file: nil, zip_file: nil, admin_set_id: nil)
      # Common initialization - load field mappings
      @mapping_manager = CsvValidationService::MappingManager.new
      @mappings = @mapping_manager.mappings

      # Determine mode and load models accordingly
      if csv_file
        # Validation mode: initialize specialized components
        @column_resolver = CsvValidationService::ColumnResolver.new(@mapping_manager)
        @csv_parser = CsvValidationService::CsvParser.new(csv_file, @column_resolver)
        @all_models = @csv_parser.extract_models
        @csv_data = @csv_parser.parse_data
        @file_validator = CsvValidationService::FileValidator.new(@csv_data, zip_file, admin_set_id)
        @item_extractor = CsvValidationService::ItemExtractor.new(@csv_data)
      else
        # Generation mode: use provided models
        @all_models = CsvValidationService::ModelLoader.new(Array.wrap(models)).models
        @csv_builder = CsvValidationService::CsvBuilder.new(self)
      end

      # Common components used by both modes
      @field_analyzer = CsvValidationService::FieldAnalyzer.new(@mappings, admin_set_id)
    end

    # ============================================================================
    # TEMPLATE GENERATION METHODS (from CsvValidationService)
    # ============================================================================

    # Generate template as a file
    #
    # @param file_path [String, nil] Path to write file (uses default if nil)
    # @return [String] Path to written file
    def to_file(file_path: nil)
      ensure_csv_builder
      file_path ||= CsvValidationService::FilePathGenerator.default_path
      @csv_builder.write_to_file(file_path)
      file_path
    end

    # Generate template as a CSV string
    #
    # @return [String] CSV content as string
    # Note: This method is primarily for testing
    def to_csv_string
      ensure_csv_builder
      @csv_builder.generate_string
    end

    # ============================================================================
    # VALIDATION METHODS (new functionality)
    # ============================================================================

    # Validate the CSV file and return comprehensive validation results
    #
    # @return [Hash] Validation results including:
    #   - headers: Array of column names in CSV
    #   - missingRequired: Array of missing required fields
    #   - unrecognized: Array of unrecognized column names
    #   - rowCount: Total number of data rows
    #   - isValid: Boolean indicating if CSV is valid
    #   - hasWarnings: Boolean indicating if there are warnings
    #   - collections: Array of collection items
    #   - works: Array of work items
    #   - fileSets: Array of file set items
    #   - totalItems: Total count of items
    #   - fileReferences: Count of file references in CSV
    #   - missingFiles: Array of referenced files not found in zip
    #   - foundFiles: Count of files found in zip
    #   - zipIncluded: Boolean indicating if zip was provided
    def validate
      # Create validator with all necessary dependencies
      validator = Validator.new(
        @csv_parser.headers,
        valid_headers_for_models,
        field_metadata_for_all_models,
        @mapping_manager,
        @file_validator
      )

      missing_required = validator.missing_required_fields
      only_rights_statement_missing = missing_required.present? &&
        missing_required.all? { |h| h[:field].to_s == 'rights_statement' }

      result = {
        headers: @csv_parser.headers,
        missingRequired: missing_required,
        unrecognized: validator.unrecognized_headers,
        rowCount: @item_extractor.total_count,
        isValid: validator.valid?,
        hasWarnings: validator.warnings?,
        collections: @item_extractor.collections,
        works: @item_extractor.works,
        fileSets: @item_extractor.file_sets,
        totalItems: @item_extractor.total_count,
        fileReferences: @file_validator.count_references,
        missingFiles: @file_validator.missing_files,
        foundFiles: @file_validator.found_files_count,
        zipIncluded: @file_validator.zip_included?
      }

      if only_rights_statement_missing && !result[:isValid]
        result[:isValid] = true
        result[:hasWarnings] = true
      end

      result
    end

    # ============================================================================
    # SHARED ANALYSIS METHODS
    # ============================================================================

    # Get comprehensive field metadata for all models in the CSV/template
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
        # Use ColumnBuilder to get all valid columns (it expects a service object)
        column_builder = CsvValidationService::ColumnBuilder.new(self)
        all_columns = column_builder.all_columns

        # Filter out ignored properties
        filtered = all_columns - CsvValidationService::CsvBuilder::IGNORED_PROPERTIES
        filtered
                         rescue StandardError => e
                           Rails.logger.error("Error building valid headers: #{e.message}")
                           # Fallback: combine all properties from all models plus standard Bulkrax fields
                           standard_fields = %w[model source_identifier parent parents file]
                           model_fields = field_metadata_for_all_models.values.flat_map { |m| m[:properties] }
                           (standard_fields + model_fields).uniq
      end
    end

    # Delegate to components
    attr_reader :field_analyzer, :mapping_manager

    private

    # Ensure CSV builder is initialized (for generation mode)
    def ensure_csv_builder
      @csv_builder ||= CsvValidationService::CsvBuilder.new(self)
    end
  end
end
