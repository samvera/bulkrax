# frozen_string_literal: true

module Bulkrax
  # Builds explanations for CSV columns
  class SampleCsvService::ExplanationBuilder
    def initialize(service)
      @service = service
      @descriptor = SampleCsvService::ColumnDescriptor.new
      @split_formatter = SampleCsvService::SplitFormatter.new
    end

    def build_explanations(header_row)
      header_row.map do |column|
        { column => build_explanation(column) }
      end
    end

    private

    def build_explanation(column)
      mapping_key = @service.mapping_manager.mapped_to_key(column)

      column_description = @descriptor.find_description_for(column)
      controlled_vocab_info = controlled_vocab_text(mapping_key)
      split_info = split_text(mapping_key, controlled_vocab_info)

      components = [
        column_description,
        controlled_vocab_info,
        split_info
      ].compact

      components.join("\n")
    end

    def controlled_vocab_text(field_name)
      vocab_terms = @service.field_analyzer.controlled_vocab_terms
      # 'location' is handled specially because its controlled vocabulary is implemented differently
      return unless vocab_terms.include?(field_name) || field_name == 'based_near'
      'This property uses a controlled vocabulary.'
    end

    def split_text(mapping_key, controlled_vocab_info)
      # regardless of schema, most controlled vocab fields only accept single values due to form limitations
      return nil if controlled_vocab_info.present? && !mapping_key.in?(%w[location resource_type])
      split_value = @service.mapping_manager.split_value_for(mapping_key)
      return nil unless split_value
      @split_formatter.format(split_value)
    end
  end
end
