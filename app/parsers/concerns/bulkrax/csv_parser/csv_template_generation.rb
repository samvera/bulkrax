# frozen_string_literal: true

module Bulkrax
  class CsvParser < ApplicationParser
    module CsvTemplateGeneration
      extend ActiveSupport::Concern

      class_methods do
        # Generate a CSV template for the specified models.
        #
        # @param models [Array<String>, String] Model names or 'all' for all available models
        # @param output [String] Output format: 'file' or 'csv_string'
        # @param admin_set_id [String, nil] Optional admin set ID for context
        # @param args [Hash] Additional arguments passed to output method (e.g., file_path)
        # @return [String] File path (for 'file' output) or CSV string (for 'csv_string' output)
        def generate_template(models: [], output: 'file', admin_set_id: nil, **args)
          raise NameError, "Hyrax is not defined" unless defined?(::Hyrax)
          TemplateContext.new(models: models, admin_set_id: admin_set_id).send("to_#{output}", **args)
        end
      end

      ##
      # Holds state for a single template generation run.
      # Provides the interface expected by CsvTemplate:: components.
      class TemplateContext
        attr_reader :mappings, :all_models, :admin_set_id, :field_analyzer, :mapping_manager

        def initialize(models: nil, admin_set_id: nil)
          @admin_set_id = admin_set_id
          @mapping_manager = CsvTemplate::MappingManager.new
          @mappings = @mapping_manager.mappings
          @field_analyzer = CsvTemplate::FieldAnalyzer.new(@mappings, admin_set_id)
          @all_models = CsvTemplate::ModelLoader.new(Array.wrap(models)).models
          @csv_builder = CsvTemplate::CsvBuilder.new(self)
        end

        def to_file(file_path: nil)
          file_path ||= CsvTemplate::FilePathGenerator.default_path(@admin_set_id)
          @csv_builder.write_to_file(file_path)
          file_path
        end

        def to_csv_string
          @csv_builder.generate_string
        end

        def field_metadata_for_all_models
          @field_metadata ||= @all_models.each_with_object({}) do |model, hash|
            field_list = @field_analyzer.find_or_create_field_list_for(model_name: model)
            hash[model] = {
              properties: field_list.dig(model, "properties") || [],
              required_terms: field_list.dig(model, "required_terms") || [],
              controlled_vocab_terms: field_list.dig(model, "controlled_vocab_terms") || []
            }
          end
        end

        def valid_headers_for_models
          @valid_headers ||= begin
            column_builder = CsvTemplate::ColumnBuilder.new(self)
            all_columns = column_builder.all_columns
            all_columns - CsvTemplate::CsvBuilder::IGNORED_PROPERTIES
          rescue StandardError => e
            Rails.logger.error("Error building valid headers: #{e.message}")
            standard_fields = %w[model source_identifier parent parents file]
            model_fields = field_metadata_for_all_models.values.flat_map { |m| m[:properties] }
            (standard_fields + model_fields).uniq
          end
        end
      end
    end
  end
end
