# frozen_string_literal: true

module Bulkrax
  # Determines values for CSV cells
  class SampleCsvService::ValueDeterminer
    def initialize(service)
      @service = service
      @column_builder = SampleCsvService::ColumnBuilder.new(service)
    end

    def determine_value(column, model_name, field_list)
      key = @service.mapping_manager.mapped_to_key(column)
      required_terms = field_list.dig(model_name, 'required_terms')

      if field_list.dig(model_name, "properties")&.include?(key)
        mark_required_or_optional(key, required_terms)
      elsif special_column?(column, key)
        special_value(column, key, model_name, required_terms)
      end
    end

    private

    def special_column?(column, key)
      descriptor = SampleCsvService::ColumnDescriptor.new
      visibility_cols = descriptor.send(:extract_column_names, :visibility)

      key.in?(['model', 'work_type']) ||
        column.in?(visibility_cols) ||
        column == 'source_identifier' ||
        column == 'rights_statement' ||
        relationship_column?(column) ||
        file_column?(column)
    end

    def special_value(column, key, model_name, required_terms)
      return SampleCsvService::ModelLoader.determine_klass_for(model_name).to_s if key.in?(['model', 'work_type'])
      return 'Required' if column == 'source_identifier'
      return mark_required_or_optional(key, required_terms) if column == 'rights_statement'
      # collections do not have files
      return nil if file_column?(column) &&  model_name.in?([Bulkrax.collection_model_class.to_s])
      'Optional'
    end

    def mark_required_or_optional(field, required_terms)
      return 'Unknown' unless required_terms
      required_terms.include?(field) ? 'Required' : 'Optional'
    end

    def relationship_column?(column)
      relationships = [
        @service.mapping_manager.find_by_flag("related_children_field_mapping", 'children'),
        @service.mapping_manager.find_by_flag("related_parents_field_mapping", 'parents')
      ]
      column.in?(relationships)
    end

    def file_column?(column)
      file_cols = SampleCsvService::ColumnDescriptor::COLUMN_DESCRIPTIONS[:files].flat_map do |property_hash|
        property_hash.keys.filter_map do |key|
          @service.mappings.dig(key, "from")&.first
        end
      end
      column.in?(file_cols)
    end
  end
end
