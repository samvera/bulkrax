# frozen_string_literal: true

module Bulkrax
  # Builds column headers for CSV
  class SampleCsvService::ColumnBuilder
    def initialize(service)
      @service = service
      @descriptor = SampleCsvService::ColumnDescriptor.new
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
                   .map { |property| @service.mapping_manager.key_to_mapped_column(property) }
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
      SampleCsvService::ColumnDescriptor::COLUMN_DESCRIPTIONS[:files].flat_map do |property_hash|
        property_hash.keys.map do |key|
          @service.mapping_manager.key_to_mapped_column(key)
        end
      end
    end
  end
end
