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

      # A mapping that lists the header in `from:` wins over one whose key
      # merely equals it, so single-field callers pick the field the CSV meant.
      def mapped_to_key(column_str)
        keys = mapped_to_keys(column_str)
        keys.find { |key| Array(Bulkrax::FieldResolver.from_value(@mappings[key])).map(&:to_s).include?(column_str.to_s) } || keys.first
      end

      def mapped_to_keys(column_str)
        Bulkrax::FieldResolver.fields_for_header(@mappings, column_str)
      end

      # Returns the `object:` value for a given mapping key, or nil. Mirrors
      # the importer-side `Bulkrax::HasMatchers#get_object_name` for callers
      # working with the template-side mapping manager.
      def get_object_name(key)
        @mappings.dig(key, "object")
      end

      # Returns the column names that target a given object name via the
      # `object:` field-mapping pattern. The template generator uses this to
      # emit the per-child columns (e.g. redirect_path, redirect_display_url)
      # instead of the bare property name (redirects). Numbering is
      # intentionally omitted — the template shows the column shape once;
      # CSV rows can repeat the column with numeric suffixes (e.g.
      # redirect_path_1, redirect_path_2) at import time.
      # An import accepts every `from:` alias, but offering them all here would
      # put two columns for the same field on the template.
      def object_columns_for(object_name)
        @mappings
          .select { |_k, v| v.is_a?(Hash) && v["object"] == object_name }
          .keys
          .map { |key| Bulkrax::FieldResolver.headers_for_field(@mappings, key).first }
          .uniq
      end

      def find_by_flag(field_name, default)
        Bulkrax::FieldResolver.flagged_key(@mappings, field_name) || default
      end

      def split_value_for(mapping_key)
        entry = @mappings[mapping_key] || {}
        entry.key?('split') ? entry['split'] : entry[:split]
      end

      def resolve_column_name(key: nil, flag: nil, default: nil)
        if flag
          mapped_key = find_by_flag(flag, nil)
          if mapped_key
            mapped_options = aliases_for(mapped_key)
            return mapped_options if mapped_options.any?
          end
        end

        if key
          mapped_options = aliases_for(key)
          return mapped_options if mapped_options.any?
        end

        default ? [default] : []
      end

      private

      # The `from:` aliases configured for `mapping_key`, without the key itself.
      def aliases_for(mapping_key)
        Array(Bulkrax::FieldResolver.from_value(@mappings[mapping_key]))
      end

      def load_mappings(include_generated:)
        raw = Bulkrax.field_mappings["Bulkrax::CsvParser"]
        return raw if include_generated

        raw.reject { |_key, value| value.is_a?(Hash) && (value["generated"] == true || value[:generated] == true) }
      end
    end
  end
end
