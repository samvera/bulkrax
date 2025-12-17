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

      components = [
        @descriptor.find_description_for(column),
        controlled_vocab_text(mapping_key),
        split_text(mapping_key)
      ].compact

      components.join("\n")
    end

    def controlled_vocab_text(field_name)
      vocab_terms = @service.field_analyzer.controlled_vocab_terms
      vocab_terms.include?(field_name) ? 'This property uses a controlled vocabulary.' : nil
    end

    def split_text(mapping_key)
      split_value = @service.mapping_manager.split_value_for(mapping_key)
      return nil unless split_value
      @split_formatter.format(split_value)
    end
  end
end
