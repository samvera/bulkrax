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
        @descriptor.core_columns.map do |column|
          @service.mapping_manager.key_to_mapped_column(column)
        end
      end

      def property_columns
        field_lists = @service.all_models.map do |m|
          @service.field_analyzer.find_or_create_field_list_for(model_name: m)
        end

        properties = field_lists
                     .flat_map { |item| item.values.flat_map { |config| config["properties"] || [] } }
                     .uniq
                     .flat_map { |property| columns_for_property(property) }
                     .uniq

        (properties - required_columns).sort
      end

      # When a property is the target of one or more `object:` field mappings,
      # emit each of those mappings' `from:` columns (e.g. redirect_path,
      # redirect_canonical, redirect_sequence) rather than the bare property
      # name (redirects). Otherwise fall back to the standard 1:1 mapping.
      def columns_for_property(property)
        nested = @service.mapping_manager.object_columns_for(property)
        return nested if nested.any?
        [@service.mapping_manager.key_to_mapped_column(property)]
      end

      def relationship_columns
        [
          @service.mapping_manager.find_by_flag("related_children_field_mapping", 'children'),
          @service.mapping_manager.find_by_flag("related_parents_field_mapping", 'parents')
        ]
      end

      def file_columns
        CsvTemplate::ColumnDescriptor::COLUMN_DESCRIPTIONS[:files].flat_map do |property_hash|
          property_hash.keys.map do |key|
            @service.mapping_manager.key_to_mapped_column(key)
          end
        end
      end
    end
  end
end
