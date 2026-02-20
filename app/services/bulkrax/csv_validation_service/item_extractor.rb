# frozen_string_literal: true

module Bulkrax
  class CsvValidationService
    ##
    # Extracts and categorizes items from CSV data
    #
    # Responsibilities:
    # - Extract collections from CSV data (with parentIds and childIds arrays)
    # - Extract works (excluding collections and file sets, with parentIds and childIds arrays)
    # - Extract file sets (without parentIds or childIds)
    # - Transform CSV rows into structured item hashes for UI display
    # - Resolve bidirectional parent-child relationships (children column infers parent relationships)
    #
    # Parent-Child Relationship Resolution:
    # - If row A has children: 'B|C', then B and C will have parentIds that include A
    # - Explicit parent values from the parent column are combined with inferred parents from children columns
    # - This ensures consistency regardless of which side of the relationship is specified in the CSV
    #
    # @example
    #   extractor = ItemExtractor.new(csv_data)
    #   extractor.collections  # => [{id: 'col1', title: 'My Collection', type: 'collection', parentIds: [], childIds: ['work1']}]
    #   extractor.works        # => [{id: 'work1', title: 'My Work', type: 'work', parentIds: ['col1'], childIds: []}]
    #   extractor.file_sets    # => [{id: 'fs1', title: 'File Set', type: 'file_set'}]
    #
    class ItemExtractor
      # Initialize the item extractor
      #
      # @param csv_data [Array<Hash>] Parsed CSV data with model, source_identifier, etc.
      def initialize(csv_data)
        @csv_data = csv_data || []
        @child_to_parent_map = build_child_to_parent_map
      end

      # Get all collection items
      #
      # @return [Array<Hash>] Array of collection items
      def collections
        items_by_model_category(:collection)
      end

      # Get all work items (excluding collections and file sets)
      #
      # @return [Array<Hash>] Array of work items with parentIds and childIds as arrays
      def works
        @csv_data.reject { |item| item_is_collection?(item) || item_is_file_set?(item) }.map do |item|
          item_id = item[:source_identifier]
          explicit_parents = parse_relationship_field(item[:parent])
          inferred_parents = @child_to_parent_map[item_id] || []

          {
            id: item_id,
            title: item[:raw_row]['title'] || item_id,
            type: 'work',
            parentIds: (explicit_parents + inferred_parents).uniq,
            childIds: parse_relationship_field(item[:children])
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
          item_id = item[:source_identifier]

          result = {
            id: item_id,
            title: item[:raw_row]['title'] || item_id,
            type: category.to_s
          }

          # Collections have parentIds and childIds (arrays), file_sets do not
          if category == :collection
            explicit_parents = parse_relationship_field(item[:parent])
            inferred_parents = @child_to_parent_map[item_id] || []

            result[:parentIds] = (explicit_parents + inferred_parents).uniq
            result[:childIds] = parse_relationship_field(item[:children])
          end

          result
        end
      end

      # Parse a relationship field (parent or children) into an array
      # Handles pipe-delimited values and returns an array
      #
      # @param field_value [String, nil] The field value from CSV
      # @return [Array<String>] Array of relationship IDs
      def parse_relationship_field(field_value)
        return [] if field_value.blank?

        # Split by pipe delimiter (Bulkrax convention for multi-value fields)
        field_value.to_s.split('|').map(&:strip).reject(&:blank?)
      end

      # Build a mapping from child IDs to their parent IDs based on the children column
      # This allows us to infer parent relationships from child relationships
      #
      # @return [Hash<String, Array<String>>] Hash mapping child IDs to array of parent IDs
      def build_child_to_parent_map
        child_to_parents = Hash.new { |h, k| h[k] = [] }

        @csv_data.each do |item|
          parent_id = item[:source_identifier]
          children = parse_relationship_field(item[:children])

          children.each do |child_id|
            child_to_parents[child_id] << parent_id
          end
        end

        child_to_parents
      end
    end
  end
end
