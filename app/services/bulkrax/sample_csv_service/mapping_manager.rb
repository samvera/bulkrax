# frozen_string_literal: true

module Bulkrax
  # Handles loading and filtering of Bulkrax field mappings
  class SampleCsvService::MappingManager
    attr_reader :mappings

    def initialize
      @mappings = load_mappings
    end

    def mapped_to_key(column_str)
      @mappings.find { |_k, v| v["from"].include?(column_str) }&.first || column_str
    end

    def key_to_mapped_column(key)
      @mappings.dig(key, "from")&.first || key
    end

    def find_by_flag(field_name, default)
      @mappings.find { |_k, v| v[field_name] == true }&.first || default
    end

    def split_value_for(mapping_key)
      @mappings.dig(mapping_key, "split")
    end

    # Generic method to find column names using multiple lookup strategies
    #
    # Tries in order:
    # 1. If flag provided, looks for mapping with that flag set to true
    # 2. Otherwise, looks up the key directly in mappings
    # 3. Returns default if nothing found
    #
    # @param key [String] The mapping key to look up (e.g., 'model', 'file')
    # @param flag [String, nil] Optional flag to search for (e.g., 'source_identifier', 'related_parents_field_mapping')
    # @param default [String] Default value to return if nothing found
    # @return [Array<String>] All possible column names from the mapping, or [default] if nothing found
    #
    # @example Direct key lookup
    #   mapping_manager.resolve_column_name(key: 'model', default: 'model')
    #   # => ['work_type', 'object_type'] (if configured) or ['model'] (default)
    #
    # @example Flag-based lookup
    #   mapping_manager.resolve_column_name(
    #     flag: 'source_identifier',
    #     default: 'source_identifier'
    #   )
    #   # => ['source_id', 'identifier', 'id'] (all options from mapping)
    def resolve_column_name(key: nil, flag: nil, default: nil)
      # Strategy 1: Look for mapping by flag
      if flag
        mapped_key = find_by_flag(flag, nil)
        if mapped_key
          mapped_options = @mappings.dig(mapped_key, "from") || []
          return mapped_options if mapped_options.any?
        end
      end

      # Strategy 2: Look up key directly in mappings
      if key
        mapped_options = @mappings.dig(key, "from") || []
        return mapped_options if mapped_options.any?
      end

      # Strategy 3: Return default array
      default ? [default] : []
    end

    private

    def load_mappings
      Bulkrax.field_mappings["Bulkrax::CsvParser"].reject do |_key, value|
        value["generated"] == true
      end
    end
  end
end
