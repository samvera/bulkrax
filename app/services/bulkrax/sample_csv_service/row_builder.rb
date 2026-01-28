# frozen_string_literal: true

module Bulkrax
  # Builds CSV rows (explanations and model data)
  class SampleCsvService::RowBuilder
    def initialize(service)
      @service = service
      @explanation_builder = SampleCsvService::ExplanationBuilder.new(service)
      @value_determiner = SampleCsvService::ValueDeterminer.new(service)
    end

    def build_explanation_row(header_row)
      @explanation_builder.build_explanations(header_row).map { |prop| prop.values.join(" ") }
    end

    def build_model_rows(header_row)
      @service.all_models.map { |m| model_breakdown(m, header_row) }
    end

    private

    def model_breakdown(model_name, header_row)
      klass = SampleCsvService::ModelLoader.determine_klass_for(model_name)
      return [] if klass.nil?

      field_list = @service.field_analyzer.find_or_create_field_list_for(model_name: model_name)

      header_row.map do |column|
        @value_determiner.determine_value(column, model_name, field_list)
      end
    end
  end
end
