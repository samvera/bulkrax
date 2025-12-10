# frozen_string_literal: true
require 'csv'

## Adds a service to generate a sample CSV file showing how fields are split
# according to the current Bulkrax field mappings for CSV imports.
# This can be used to help users understand how to format their CSV files
# for import into Bulkrax.
#
# WARNING: There may be some odd results if some of the custom properties are not
# defined in the bulkrax mappings, or if defined differently than expected.
#
# Example usage:
#   # To create a CSV file on disk
#   Bulkrax::SampleCsvService.call(output: 'file', model_name: 'all')
#   Bulkrax::SampleCsvService.call(output: 'file', model_name: 'ImageResource')
#   Bulkrax::SampleCsvService.call(output: 'file', model_name: 'ImageResource', file_path: '/path/to/save/bulkrax_template.csv')
#
#   # To get a CSV string for download via a controller
#   csv_string = Bulkrax::SampleCsvService.call(output: 'csv_string', model_name: 'all')
#
# Controller example to download the CSV file:
#   class BulkraxController < ApplicationController
#     def download_sample_csv
#       csv_data = Bulkrax::SampleCsvService.to_csv_string
#       send_data csv_data,
#         filename: "bulkrax_split_info.csv",
#         type: "text/csv"
#     end
#   end

# rubocop:disable Metrics/ClassLength
module Bulkrax
  class SampleCsvService
    ADDED_BULKRAX_PROPERTIES = [
      { 'visibility' => 'Uses Importer if not present (open, institution, restricted, embargo, or lease)' },
      { 'embargo_release_date' => 'Required for embargo (2028-02-24)' },
      { 'visibility_during_embargo' => 'Required for embargo' },
      { 'visibility_after_embargo' => 'Required for embargo' },
      { 'lease_expiration_date' => 'Required for lease (2028-02-24)' },
      { 'visibility_during_lease' => 'Required for lease' },
      { 'visibility_after_lease' => 'Required for lease' }
    ].freeze

    SPECIAL_PROPERTIES = [
      { 'model OR work_type' => 'Default if not present' },
      { 'source_identifier' => 'Required unique alternative to id' }
    ].freeze

    ## Initialize with optional model_name to customize mappings
    #
    # @param model_name [Class, nil, String] the model_name class to use for mappings
    #               Defaults to nil, which uses general CSV parser mappings
    #               Processes all model_names if 'all' is passed
    # @return [Bulkrax::SampleCsvService] the service instance
    def initialize(model_name: nil)
      # don't include generated metadata fields, except rights_statement
      @mappings = Bulkrax.field_mappings["Bulkrax::CsvParser"].reject do |key, value|
        value["generated"] == true && key != 'rights_statement'
      end
      # load models if 'all' is specified for model_name
      @model_name = model_name
      @all_models = begin
                      if model_name == 'all' && defined?(::Hyrax)
                        Hyrax.config.curation_concerns + [Bulkrax.collection_model_class, Bulkrax.file_model_class]
                      else
                        [Bulkrax.default_work_type, Bulkrax.collection_model_class, Bulkrax.file_model_class]
                      end
                    rescue
                      []
                    end
    end

    ## Generate the CSV file or string
    #
    # @param model_name [Class, nil, String] the model class to use for mappings
    # Defaults to nil, which uses general CSV parser mappings
    # @return [File] A CSV file on disk if output is 'file'
    # @return [String] A CSV string if output is 'csv_string'
    def self.call(model_name: nil, output: 'file', **args)
      new(model_name: model_name).send("to_#{output}", **args)
    end

    ## create a CSV file on disk and create a Bulkrax Importer for it
    def to_file(file_path: nil)
      file_path ||= Rails.root.join('tmp', 'imports', filename)
      CSV.open(file_path, "w") do |csv|
        csv_rows.each { |row| csv << row }
      end
      to_importer(file_path: file_path)
    end

    ## create a CSV string for download via controller action
    def to_csv_string
      CSV.generate do |csv|
        csv_rows.each { |row| csv << row }
      end
    end

    private

    def filename
      "bulkrax_template_#{@model_name.downcase}_#{Time.now.utc.strftime('%Y%m%d_%H%M%S')}.csv"
    end

    ## create a Bulkrax Importer using the generated CSV file
    def to_importer(file_path:)
      Bulkrax::Importer.create(
        name: "Sample CSV #{Time.now.utc.to_date}",
        admin_set_id: Hyrax::AdminSetCreateService.find_or_create_default_admin_set.id,
        user_id: User.find_by(email: 'admin@example.com').id,
        frequency: 'PT0S',
        parser_klass: 'Bulkrax::CsvParser',
        parser_fields: {
          'visibility' => 'open',
          'rights_statement' => '',
          'override_rights_statement' => '0',
          'file_style' => 'Specify a Path on the Server',
          'import_file_path' => file_path,
          'update_files' => false
        }
      )
    end

    def csv_rows
      @breakdown_mappings ||= breakdown_mappings
      # Combine arrays and remove ignored properties in one step
      @header_row ||= @breakdown_mappings.map { |mapping| mapping.keys.first }
      split_row = @breakdown_mappings.map { |mapping| mapping.values.first }
      rows_for_model = @model_name ? model_rows : []

      [@header_row, split_row] + rows_for_model
    end

    # @TODO: ensure that bulkrax mappings include all properties for the model
    # even if not mapped in Bulkrax settings
    # rubocop:disable Metrics/MethodLength
    def breakdown_mappings
      # start with the required Bulkrax properties, then
      # add the bulkrax_mapped properties
      all_mappings = ADDED_BULKRAX_PROPERTIES +
                     @mappings.map do |_, value|
                       split_text = format_split_text(value["split"])
                       { value["from"].join(' OR ') => split_text }
                     end
      # add in special properties
      SPECIAL_PROPERTIES + all_mappings
    end

    def format_split_text(split_value)
      return "does not split" if split_value.nil?
      if split_value == true
        # use global setting
        parse_split_pattern(Bulkrax.multi_value_element_split_on.source)
      elsif split_value.is_a?(String)
        # use custom setting
        parse_split_pattern(split_value)
      else
        # does not match identified patterns
        split_value
      end
    end

    def parse_split_pattern(pattern)
      if (match = pattern.match(/\[([^\]]+)\]/))
        "split on #{match[1]}"
      elsif (single = pattern.match(/\\(.)/))
        "split on #{single[1]}"
      else
        "split on #{pattern}"
      end
    end

    # Generate rows for the specified model or all models
    def model_rows
      case @model_name
      when 'all'
        @all_models.map { |m| model_breakdown(m.name) }
      when String
        [model_breakdown(@model_name)]
      else
        []
      end
    end

    # rubocop:disable Metrics/MethodLength
    def model_breakdown(model_name)
      model_row = []
      klass = determine_klass_for(model_name)
      return model_row if klass.nil?

      field_list = if klass.respond_to?(:schema)
                     Bulkrax::ValkyrieObjectFactory.schema_properties(klass).map(&:to_sym)
                   else
                     klass.properties.keys.map(&:to_sym)
                   end
      load_required_terms_for(klass: klass)

      @header_row.each do |column_heading|
        # Load a value into each column based on the heading
        value = if field_list.include?(column_heading.to_sym)
                  mark_property(field: column_heading.to_sym)
                elsif column_heading == 'model' || column_heading == 'work_type' || column_heading == 'model OR work_type'
                  model_name.to_s
                elsif column_heading.in?(ADDED_BULKRAX_PROPERTIES.map(&:keys).flatten)
                  'Optional'
                elsif column_heading == 'source_identifier'
                  'Required'
                elsif column_heading == 'children' || column_heading == 'parents'
                  'Related entries (id or source_identifier)'
                elsif column_heading == 'file' || column_heading == 'remote_files'
                  'File names or URLs'
                else
                  'N/A'
                end
        model_row << value
      end
      model_row
    end
    # rubocop:enable Metrics/MethodLength

    # Determine if the property is required or optional for the given class
    def mark_property(field:)
      return 'Unknown' unless @required_terms
      return 'Required' if @required_terms.include?(field)
      'Optional'
    end

    def load_required_terms_for(klass:)
      @required_terms = begin
                          if klass.respond_to?(:schema)
                            schema = klass.new.singleton_class.schema || klass.schema
                            get_required_types(schema)
                          else
                            []
                          end
                        rescue
                          []
                        end
    end

    def get_required_types(schema)
      schema.select do |key|
        next false unless key.respond_to?(:meta) &&
                          key.meta["form"].is_a?(Hash) &&
                          key.meta["form"]["required"] == true
        true
      end.map(&:name)
    end

    def determine_klass_for(model_name)
      return model_name.constantize unless Bulkrax.config.object_factory == Bulkrax::ValkyrieObjectFactory
      Valkyrie.config.resource_class_resolver.call(model_name)
    rescue
      nil
    end
  end
end
# rubocop:enable Metrics/ClassLength
