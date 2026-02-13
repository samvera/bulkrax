# frozen_string_literal: true

module Bulkrax
  class CsvValidationService
    ##
    # Parses CSV files and extracts structured data for validation
    #
    # Responsibilities:
    # - Read CSV file headers
    # - Parse CSV rows into structured data
    # - Extract unique model names from CSV
    # - Handle both File and UploadedFile types
    #
    # @example
    #   parser = CsvParser.new(csv_file, column_resolver)
    #   parser.headers                  # => ['model', 'title', 'creator']
    #   parser.extract_models           # => ['GenericWork', 'Collection']
    #   parser.parse_data               # => [{source_identifier: 'work1', model: 'GenericWork', ...}]
    #
    class CsvParser
      attr_reader :csv_file

      # Initialize the CSV parser
      #
      # @param csv_file [File, ActionDispatch::Http::UploadedFile] CSV file to parse
      # @param column_resolver [ColumnResolver] Resolver for finding column names
      def initialize(csv_file, column_resolver)
        @csv_file = csv_file
        @column_resolver = column_resolver
      end

      # Get headers from the CSV file
      #
      # @return [Array<String>] Array of header names
      def headers
        @headers ||= begin
          return [] unless @csv_file
          CSV.open(file_path, &:first) || []
        end
      end

      # Extract unique model names from the CSV file
      #
      # @return [Array<String>] Array of unique model names found in CSV
      def extract_models
        @extracted_models ||= begin
          return [] unless @csv_file

          model_column = @column_resolver.model_column_name(headers)
          models = Set.new

          CSV.foreach(file_path, headers: true) do |row|
            model_value = row[model_column]
            models << model_value if model_value.present?
          end

          models.to_a.compact
                              rescue StandardError => e
                                Rails.logger.error("Error extracting models from CSV: #{e.message}")
                                []
        end
      end

      # Parse CSV data into structured format for validation
      #
      # @return [Array<Hash>] Array of hashes representing each CSV row with:
      #   - source_identifier: Unique identifier for the item
      #   - model: Model type
      #   - parent: Parent identifier
      #   - file: File reference
      #   - raw_row: Original CSV row object
      def parse_data
        @parsed_data ||= begin
          return [] unless @csv_file

          model_col = @column_resolver.model_column_name(headers)
          source_id_col = @column_resolver.source_identifier_column_name(headers)
          parent_col = @column_resolver.parent_column_name(headers)
          file_col = @column_resolver.file_column_name(headers)

          CSV.read(file_path, headers: true).map do |row|
            {
              source_identifier: row[source_id_col],
              model: row[model_col],
              parent: row[parent_col],
              file: row[file_col],
              raw_row: row
            }
          end
                         rescue StandardError => e
                           Rails.logger.error("Error parsing CSV data: #{e.message}")
                           []
        end
      end

      private

      # Get the path to the CSV file (handles both File and UploadedFile)
      #
      # @return [String] Path to CSV file
      def file_path
        @csv_file.respond_to?(:path) ? @csv_file.path : @csv_file
      end
    end
  end
end
