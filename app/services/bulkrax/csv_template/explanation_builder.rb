# frozen_string_literal: true

module Bulkrax
  module CsvTemplate
    # Builds explanations for CSV columns
    class ExplanationBuilder
      def initialize(service)
        @service = service
        @descriptor = CsvTemplate::ColumnDescriptor.new
        @split_formatter = CsvTemplate::SplitFormatter.new
      end

      def build_explanations(header_row)
        header_row.map do |column|
          { column => build_explanation(column) }
        end
      end

      private

      def build_explanation(column)
        mapping_key = @service.mapping_manager.mapped_to_key(column)

        column_description = source_identifier_description(column) || @descriptor.find_description_for(column)
        controlled_vocab_info = controlled_vocab_text(mapping_key)
        split_info = split_text(mapping_key, controlled_vocab_info)

        components = [
          column_description,
          controlled_vocab_info,
          split_info
        ].compact

        components.join("\n")
      end

      def source_identifier_description(column)
        return unless @service.mapping_manager.mapped_to_key(column) == 'source_identifier'
        return if Bulkrax.fill_in_blank_source_identifiers.blank?
        "Will be auto-generated if left blank.\nProviding one allows round-tripping and deduplication across imports."
      end

      def controlled_vocab_text(field_name)
        vocab_terms = @service.field_analyzer.controlled_vocab_terms
        return unless vocab_terms.include?(field_name) || field_name == 'based_near'
        'This property uses a controlled vocabulary.'
      end

      def split_text(mapping_key, controlled_vocab_info)
        return nil if controlled_vocab_info.present? && !mapping_key.in?(%w[location resource_type])
        split_value = @service.mapping_manager.split_value_for(mapping_key)
        return nil unless split_value
        @split_formatter.format(split_value)
      end
    end
  end
end
