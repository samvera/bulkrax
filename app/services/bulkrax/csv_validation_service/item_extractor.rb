# frozen_string_literal: true

module Bulkrax
  class CsvValidationService
    ##
    # Extracts and categorizes items from CSV data
    #
    # Responsibilities:
    # - Extract collections from CSV data
    # - Extract works (excluding collections and file sets)
    # - Extract file sets
    # - Transform CSV rows into structured item hashes for UI display
    #
    # @example
    #   extractor = ItemExtractor.new(csv_data)
    #   extractor.collections  # => [{id: 'col1', title: 'My Collection', type: 'collection'}]
    #   extractor.works        # => [{id: 'work1', title: 'My Work', type: 'work'}]
    #   extractor.file_sets    # => [{id: 'fs1', title: 'File Set', type: 'file_set'}]
    #
    class ItemExtractor
      # Initialize the item extractor
      #
      # @param csv_data [Array<Hash>] Parsed CSV data with model, source_identifier, etc.
      def initialize(csv_data)
        @csv_data = csv_data || []
      end

      # Get all collection items
      #
      # @return [Array<Hash>] Array of collection items
      def collections
        items_by_model_type('Collection')
      end

      # Get all work items (excluding collections and file sets)
      #
      # @return [Array<Hash>] Array of work items
      def works
        excluded_types = ['Collection', 'FileSet']
        @csv_data.reject { |item| excluded_types.include?(item[:model]) }.map do |item|
          {
            id: item[:source_identifier],
            title: item[:raw_row]['title'] || item[:source_identifier],
            type: 'work',
            parentId: item[:parent]
          }
        end
      end

      # Get all file set items
      #
      # @return [Array<Hash>] Array of file set items
      def file_sets
        items_by_model_type('FileSet')
      end

      # Get total count of all items
      #
      # @return [Integer] Total number of items in CSV
      def total_count
        @csv_data.length
      end

      private

      # Get items filtered by model type
      #
      # @param type [String] Model type to filter by (e.g., 'Collection', 'Work', 'FileSet')
      # @return [Array<Hash>] Array of items matching the type
      def items_by_model_type(type)
        @csv_data.select { |item| item[:model] == type }.map do |item|
          {
            id: item[:source_identifier],
            title: item[:raw_row]['title'] || item[:source_identifier],
            type: type.underscore,
            parentId: item[:parent]
          }
        end
      end
    end
  end
end
