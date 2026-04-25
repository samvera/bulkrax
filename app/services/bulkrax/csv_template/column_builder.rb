# frozen_string_literal: true

module Bulkrax
  module CsvTemplate
    # Builds column headers for CSV
    class ColumnBuilder
      def initialize(service)
        @service = service
        @descriptor = CsvTemplate::ColumnDescriptor.new
      end

      def all_columns
        required_columns + property_columns
      end

      def required_columns
        mapped_core_columns +
          relationship_columns +
          file_columns
      end

      private

      def mapped_core_columns
        @descriptor.core_columns.map { |column| header_for(column) }
      end

      def property_columns
        field_lists = @service.all_models.map do |m|
          @service.field_analyzer.find_or_create_field_list_for(model_name: m)
        end

        properties = field_lists
                     .flat_map { |item| item.values.flat_map { |config| config["properties"] || [] } }
                     .uniq
                     .map { |property| header_for(property) }
                     .uniq

        (properties - required_columns).sort
      end

      def relationship_columns
        [
          @service.mapping_manager.find_by_flag("related_children_field_mapping", 'children'),
          @service.mapping_manager.find_by_flag("related_parents_field_mapping", 'parents')
        ]
      end

      def file_columns
        CsvTemplate::ColumnDescriptor::COLUMN_DESCRIPTIONS[:files].flat_map do |property_hash|
          property_hash.keys.map { |key| header_for(key) }
        end
      end

      # Picks one CSV column header to emit for a canonical mapping key.
      # Any of the key's `from:` aliases (or the key itself) is a valid
      # header — see Bulkrax::FieldResolver.headers_for_field.
      def header_for(key)
        Bulkrax::FieldResolver.headers_for_field(@service.mappings, key).first
      end
    end
  end
end
