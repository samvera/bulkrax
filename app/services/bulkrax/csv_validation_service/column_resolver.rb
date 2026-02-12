# frozen_string_literal: true

module Bulkrax
  class CsvValidationService
    ##
    # Resolves CSV column names from Bulkrax field mappings
    #
    # Responsibilities:
    # - Find which CSV column corresponds to semantic fields (model, source_identifier, etc.)
    # - Handle custom field mappings configured in Bulkrax
    # - Provide fallback to common column name variations
    #
    # This class delegates to MappingManager's generic resolve_column_name method,
    # providing a focused interface for CSV column name resolution.
    #
    # The service handles cases where users may have configured custom mappings like:
    #   'model' => { from: ['work_type'] }
    #   'source_identifier' => { from: ['source_id'] }
    #
    # @example
    #   mapping_manager = SampleCsvService::MappingManager.new
    #   resolver = ColumnResolver.new(mapping_manager)
    #   resolver.model_column_name(['work_type', 'title'])      # => 'work_type'
    #   resolver.source_identifier_column_name(['source_id', 'title']) # => 'source_id'
    #
    class ColumnResolver
      # Initialize the column resolver
      #
      # @param mapping_manager [SampleCsvService::MappingManager] Mapping manager instance
      def initialize(mapping_manager)
        @mapping_manager = mapping_manager
      end

      # Find the CSV column name used for model information
      #
      # @param csv_headers [Array<String>] Available CSV headers
      # @return [String] Column name for model field
      def model_column_name(csv_headers = [])
        options = @mapping_manager.resolve_column_name(key: 'model', default: 'model')
        find_first_match(options, csv_headers)
      end

      # Find the CSV column name used for source identifier
      #
      # @param csv_headers [Array<String>] Available CSV headers
      # @return [String] Column name for source identifier
      def source_identifier_column_name(csv_headers = [])
        options = @mapping_manager.resolve_column_name(flag: 'source_identifier', default: 'source_identifier')
        find_first_match(options, csv_headers)
      end

      # Find the CSV column name used for parent relationships
      #
      # @param csv_headers [Array<String>] Available CSV headers
      # @return [String] Column name for parent field
      def parent_column_name(csv_headers = [])
        options = @mapping_manager.resolve_column_name(flag: 'related_parents_field_mapping', default: 'parents')
        find_first_match(options, csv_headers)
      end

      # Find the CSV column name used for file references
      #
      # @param csv_headers [Array<String>] Available CSV headers
      # @return [String] Column name for file field
      def file_column_name(csv_headers = [])
        options = @mapping_manager.resolve_column_name(key: 'file', default: 'file')
        find_first_match(options, csv_headers)
      end

      private

      # Find the first option that exists in csv_headers, or return first option
      def find_first_match(options, csv_headers)
        if csv_headers.any?
          options.find { |opt| csv_headers.include?(opt) } || options.first
        else
          options.first
        end
      end
    end
  end
end
