# frozen_string_literal: true

module Bulkrax
  module CsvTemplate
    # Handles loading and filtering of Bulkrax field mappings
    class MappingManager
      attr_reader :mappings

      # @param include_generated [Boolean] when false, excludes mapping entries
      #   flagged `generated: true` (system-maintained fields like
      #   date_uploaded, depositor, source_identifier). Template generation
      #   passes +false+ so the downloadable template doesn't expose
      #   system columns; import validation uses the default +true+ so that
      #   user-configured mappings like `rights_statement` (which Bulkrax
      #   ships with `generated: true`) are still recognised when the CSV
      #   uses one of their `from:` aliases.
      def initialize(include_generated: true)
        @mappings = load_mappings(include_generated: include_generated)
      end

      def mapped_to_key(column_str)
        @mappings.find { |_k, v| v["from"].include?(column_str) }&.first || column_str
      end

      def find_by_flag(field_name, default)
        @mappings.find { |_k, v| v[field_name] == true }&.first || default
      end

      def split_value_for(mapping_key)
        @mappings.dig(mapping_key, "split")
      end

      def resolve_column_name(key: nil, flag: nil, default: nil)
        if flag
          mapped_key = find_by_flag(flag, nil)
          if mapped_key
            mapped_options = @mappings.dig(mapped_key, "from") || []
            return mapped_options if mapped_options.any?
          end
        end

        if key
          mapped_options = @mappings.dig(key, "from") || []
          return mapped_options if mapped_options.any?
        end

        default ? [default] : []
      end

      private

      def load_mappings(include_generated:)
        raw = Bulkrax.field_mappings["Bulkrax::CsvParser"]
        return raw if include_generated

        raw.reject { |_key, value| value["generated"] == true }
      end
    end
  end
end
