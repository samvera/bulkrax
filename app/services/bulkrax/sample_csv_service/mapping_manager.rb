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

    private

    def load_mappings
      Bulkrax.field_mappings["Bulkrax::CsvParser"].reject do |_key, value|
        value["generated"] == true
      end
    end
  end
end
