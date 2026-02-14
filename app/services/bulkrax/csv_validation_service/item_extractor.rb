# frozen_string_literal: true

module Bulkrax
  class CsvValidationService
    ##
    # Extracts and categorizes items from CSV data
    #
    # Responsibilities:
    # - Extract collections from CSV data (with parentIds array)
    # - Extract works (excluding collections and file sets, with parentIds array)
    # - Extract file sets (without parentIds)
    # - Transform CSV rows into structured item hashes for UI display
    #
    # @example
    #   extractor = ItemExtractor.new(csv_data)
    #   extractor.collections  # => [{id: 'col1', title: 'My Collection', type: 'collection', parentIds: []}]
    #   extractor.works        # => [{id: 'work1', title: 'My Work', type: 'work', parentIds: ['col1']}]
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
        items_by_model_category(:collection)
      end

      # Get all work items (excluding collections and file sets)
      #
      # @return [Array<Hash>] Array of work items with parentIds as array
      def works
        @csv_data.reject { |item| item_is_collection?(item) || item_is_file_set?(item) }.map do |item|
          {
            id: item[:source_identifier],
            title: item[:raw_row]['title'] || item[:source_identifier],
            type: 'work',
            parentIds: item[:parent].present? ? [item[:parent]] : []
          }
        end
      end

      # Get all file set items
      #
      # @return [Array<Hash>] Array of file set items
      def file_sets
        items_by_model_category(:file_set)
      end

      # Get total count of all items
      #
      # @return [Integer] Total number of items in CSV
      def total_count
        @csv_data.length
      end

      private

      # Check if an item is a collection
      #
      # @param item [Hash] CSV item with :model key
      # @return [Boolean]
      def item_is_collection?(item)
        return false unless item[:model]

        resolved_klass = CsvValidationService::ModelLoader.determine_klass_for(item[:model])
        return false unless resolved_klass

        collection_klass = Bulkrax.collection_model_class
        return false unless collection_klass

        resolved_klass == collection_klass || resolved_klass.name == collection_klass.name
      end

      # Check if an item is a file set
      #
      # @param item [Hash] CSV item with :model key
      # @return [Boolean]
      def item_is_file_set?(item)
        return false unless item[:model]

        resolved_klass = CsvValidationService::ModelLoader.determine_klass_for(item[:model])
        return false unless resolved_klass

        file_klass = Bulkrax.file_model_class
        return false unless file_klass

        resolved_klass == file_klass || resolved_klass.name == file_klass.name
      end

      # Get items filtered by model category (collection or file_set)
      #
      # @param category [Symbol] Either :collection or :file_set
      # @return [Array<Hash>] Array of items matching the category
      def items_by_model_category(category)
        predicate = case category
                    when :collection
                      ->(item) { item_is_collection?(item) }
                    when :file_set
                      ->(item) { item_is_file_set?(item) }
                    else
                      ->(_item) { false }
                    end

        @csv_data.select { |item| predicate.call(item) }.map do |item|
          result = {
            id: item[:source_identifier],
            title: item[:raw_row]['title'] || item[:source_identifier],
            type: category.to_s
          }

          # Collections and works have parentIds (array), file_sets do not
          result[:parentIds] = item[:parent].present? ? [item[:parent]] : [] if category == :collection

          result
        end
      end
    end
  end
end
