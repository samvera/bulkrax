# frozen_string_literal: true
require 'csv'

## Adds a service to generate a sample CSV file showing how fields are split
# according to the current Bulkrax field mappings for CSV imports.
# This can be used to help users understand how to format their CSV files
# for import into Bulkrax.
#
# WARNINGS:
# - There may be some odd results if some of the custom properties are not
#   defined in the bulkrax mappings, or if defined differently than expected.
# - Requires Hyrax to be defined.
#
# Example usage:
#   # To create a CSV file on disk & an Importer using it
#   Bulkrax::SampleCsvService.call(output: 'file', model_name: 'all')
#   Bulkrax::SampleCsvService.call(output: 'file', model_name: 'ImageResource')
#   Bulkrax::SampleCsvService.call(output: 'file', model_name: 'ImageResource', file_path: '/path/to/save/bulkrax_template.csv')
#
#   # To get a CSV string for download via a controller
#   csv_string = Bulkrax::SampleCsvService.call(output: 'csv_string', model_name: 'all')
#   end

# rubocop:disable Metrics/ClassLength
module Bulkrax
  class SampleCsvService
    # Include these columns with descriptions first in the sample CSV
    HIGHLIGHTED_PROPERTIES = [
      { "work_type" => "The work types configured in your repository are listed below.\nIf left blank, your default work type, #{Bulkrax.default_work_type}, is used." },
      { "source_identifier" => "This must be a unique identifier.\nIt can be alphanumeric with some special charaters (e.g. hyphens, colons), and URLs are also supported." },
      { "id" => "This column would optionally be included only if it is a re-import, i.e. for updating or deleting records.\nThis is a key identifier used by the system, which you wouldn't have for new imports." },
      { "rights_statement" => "Rights statement URI for the work.\nIf not included, uses the value specified on the bulk import configuration screen." }
    ].freeze

    FILE_PROPERTIES = [
      { "file" => "Use filenames exactly matching those in your files folder.\nZip your CSV and files folder together and attach this to your importer." },
      { "remote_files" => "Use the URLs to remote files to be attached to the work." }
    ].freeze

    # add properties related to setting visibility
    VISIBILITY_PROPERTIES = [
      { "visibility" => "Uses the value specified on the bulk import configuration screen if not added here.\nValid options: open, institution, restricted, embargo, lease" },
      { "embargo_release_date" => "Required for embargo (yyyy-mm-dd)" },
      { "visibility_during_embargo" => "Required for embargo" },
      { "visibility_after_embargo" => "Required for embargo" },
      { "lease_expiration_date" => "Required for lease (yyyy-mm-dd)" },
      { "visibility_during_lease" => "Required for lease" },
      { "visibility_after_lease" => "Required for lease" }
    ].freeze

    # properties which we don't import via CSV and want to exclude from the sample output
    IGNORED_PROPERTIES = %w[
      admin_set_id
      alternate_ids
      arkivo_checksum
      created_at
      date_modified
      date_uploaded
      depositor
      embargo
      has_model
      head
      internal_resource
      is_child
      lease
      member_ids
      member_of_collection_ids
      modified_date
      new_record
      on_behalf_of
      owner
      proxy_depositor
      rendering_ids
      representative_id
      split_from_pdf_id
      state
      tail
      thumbnail_id
      updated_at
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
        value["generated"] == true # && key != 'rights_statement'
      end
      # load models if 'all' is specified for model_name
      @all_models = begin
                      case model_name
                        when nil
                          []
                        when 'all'
                          Hyrax.config.curation_concerns.map(&:name) + [Bulkrax.collection_model_class&.name, Bulkrax.file_model_class&.name]
                        else
                          [model_name] if model_name.constantize
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
      raise NameError, "Hyrax is not defined" unless defined?(::Hyrax)
      new(model_name: model_name).send("to_#{output}", **args)
    end

    ## create a CSV file on disk
    def to_file(file_path: nil)
      file_path ||= Rails.root.join('tmp',
                                    'imports',
                                    "bulkrax_template_#{Time.now.utc.strftime('%Y%m%d_%H%M%S')}.csv")
      CSV.open(file_path, "w") do |csv|
        csv_rows.each { |row| csv << row }
      end
    end

    ## create a CSV string for download via controller action
    def to_csv_string
      CSV.generate do |csv|
        csv_rows.each { |row| csv << row }
      end
    end

    ## create a Bulkrax Importer using the generated CSV file
    def to_importer(file_path: nil)
      file_path ||= Rails.root.join('tmp',
                              'imports',
                              "bulkrax_template_#{Time.now.utc.strftime('%Y%m%d_%H%M%S')}.csv")
      to_file(file_path: file_path)

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

    private

    ## Generate all the rows for the CSV file
    def csv_rows
      @header_row = fill_header_row
      explanation_row = property_explanations.map { |prop| prop.values.join(" ") }
      rows_for_model_array = @all_models.map { |m| model_breakdown(m) }
      rows = [@header_row, explanation_row] + rows_for_model_array
      remove_empty_columns(rows)
    end

    ## Generate the header row for the CSV file
    def fill_header_row
      # get the field list for all models
      field_lists = @all_models.map { |m| find_or_create_field_list_for(model_name: m) }

      # Extract keys from hashes, and validate against bulkrax field mappings
      highlighted_terms = HIGHLIGHTED_PROPERTIES.map { |hash| hash.keys.first }
      visibility_terms = VISIBILITY_PROPERTIES.map { |hash| hash.keys.first }

      # Merge all properties from all models, map them, then remove ignored properties
      merged_properties = field_lists
        .flat_map { |item| item.values.flat_map { |config| config["properties"] || [] } }
        .uniq
        .map { |property| key_to_mapped_column(property) }
        .uniq - IGNORED_PROPERTIES

      # Remove highlighted and visibility properties, then sort alphabetically
      remaining_properties = (merged_properties - highlighted_terms - visibility_terms).sort
      @required_headings = highlighted_terms + visibility_terms + relationship_properties + file_terms

      # Combine in the desired order
      highlighted_terms +
        visibility_terms +
        relationship_properties +
        file_terms +
        remaining_properties
    end

    def file_terms
      @file_terms ||FILE_PROPERTIES.flat_map do |property_hash|
        property_hash.keys.map do |key|
           @mappings[key]["from"].first if @mappings[key]
        end
      end.compact
    end

    def relationship_properties
      @relationship_properties ||= [
        find_mapping_key("related_children_field_mapping", 'children'),
        find_mapping_key("related_parents_field_mapping", 'parents')
      ]
    end

    def find_mapping_key(field_name, default)
      @mappings.find { |k, v| v[field_name] == true }&.first || default
    end

    ## Collate a field list of properties and other needed information for all models
    # Returns an array of hashes with model names as keys and field lists as values
    # [{ 'ImageResource' => { properties: ['title', 'creator', ...], required_terms: [...], controlled_vocab_terms: [...] }},
    #  { 'Collection' => { properties: ['title', 'description', ...], required_terms: [...], controlled_vocab_terms: [...] }}]
    def find_or_create_field_list_for(model_name:)
      @field_list ||= []

      # Check if this model is already in the array
      existing_entry = @field_list.find { |entry| entry.key?(model_name) }
      return existing_entry if existing_entry.present?

      klass = determine_klass_for(model_name)
      return {} if klass.nil?

      # Get the properties for this model as strings
      properties = if klass.respond_to?(:schema)
                    Bulkrax::ValkyrieObjectFactory.schema_properties(klass).map(&:to_s)
                  else
                    klass.properties.keys.map(&:to_s)
                  end

      # Get the required terms for this model as strings
      required_terms = load_required_terms_for(klass: klass)
      vocab_terms = load_controlled_vocab_terms_for(klass: klass)

      # Create the hash entry for this model with string keys
      model_entry = {
        model_name => {
          'properties' => properties,
          'required_terms' => required_terms,
          'controlled_vocab_terms' => vocab_terms
        }
      }

      # Add to the array and return the entry
      @field_list << model_entry
      model_entry
    end

    def model_breakdown(model_name)
      model_row = []
      klass = determine_klass_for(model_name)
      return model_row if klass.nil?
      field_list_entry = find_or_create_field_list_for(model_name: model_name)
      @required_terms = field_list_entry.dig(model_name, 'required_terms')

      @header_row.each do |column_heading|
        # look up the actual property from the model this column maps to
        key = mapped_to_key(column_heading)
        # Load a value into each column based on the heading
        value = if field_list_entry.dig(model_name, "properties")&.include?(key)
                  mark_required_or_optional(field: key)
                elsif key == 'model' || key == 'work_type'
                  determine_klass_for(model_name).to_s
                elsif column_heading.in?(VISIBILITY_PROPERTIES.map(&:keys).flatten)
                  'Optional'
                elsif column_heading == 'source_identifier'
                  'Required'
                elsif column_heading == 'rights_statement'
                  mark_required_or_optional(field: key)
                elsif column_heading.in?(relationship_properties)
                  'Optional'
                elsif column_heading.in?(file_terms)
                  'Optional'
                else
                  '---'
                end
        model_row << value
      end
      model_row
    end

    ## Generate breakdown of mappings with split info and descriptions
    def property_explanations
      # We don't currently vary property definitions by model, so we just do this once for all models
      @controlled_vocab_terms = @field_list.flat_map do |hash|
        hash.values.flat_map { |model_data| model_data["controlled_vocab_terms"] || [] }
      end.uniq

      result = @header_row.map do |column_str|
        mapping_key = mapped_to_key(column_str)

        split_text = nil
        description = nil
        vocab_text = nil

        # Get split value from mappings if it exists
        if @mappings[mapping_key] && @mappings[mapping_key]["split"]
          split_text = format_split_text(@mappings[mapping_key]["split"])
        end

        # Find description in HIGHLIGHTED_PROPERTIES or VISIBILITY_PROPERTIES
        highlighted_prop = HIGHLIGHTED_PROPERTIES.find { |hash| hash.key?(column_str) }
        description = highlighted_prop[column_str] if highlighted_prop
        # If not found in HIGHLIGHTED, check VISIBILITY_PROPERTIES
        unless description
          visibility_prop = VISIBILITY_PROPERTIES.find { |hash| hash.key?(column_str) }
          description = visibility_prop[column_str] if visibility_prop
        end

        # Add description for relationship properties
        if column_str.in?(relationship_properties)
          description = 'Contains the id or source_identifier of related objects.'
        end

        # Add description for file properties
        if column_str.in?(file_terms)
          key = mapped_to_key(column_str)
          file_prop = FILE_PROPERTIES.find { |hash| hash.key?(key) }
          description = file_prop[key] if file_prop
        end

        # Add description for controlled vocabulary properties
        vocab_text = uses_controlled_vocab?(mapping_key) ? 'This property uses a controlled vocabulary.' : nil

        # Concatenate split and description text
        combined_text = [description, vocab_text, split_text].compact.join("\n")

        # Return hash with column as key and combined text as value
        { column_str => combined_text }
      end.compact
    end

    def mapped_to_key(column_str)
       @mappings.find { |k, v| v["from"].include?(column_str) }&.first || column_str
    end

    def key_to_mapped_column(key)
      @mappings.dig(key, "from")&.first || key
    end

    def format_split_text(split_value)
      return "Property does not split." if split_value.nil?
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
      split_values = if (match = pattern.match(/\[([^\]]+)\]/))
                       match[1]
                     elsif (single = pattern.match(/\\(.)/))
                       single[1]
                     else
                       pattern
                     end

      "Split multiple values with #{split_values.chars.then { |c| c.length > 1 ? c[0..-2].join(" ") + " or " + c.last : c.first }}"
    end

    def mark_required_or_optional(field:)
      return 'Unknown' unless @required_terms
      return 'Required' if @required_terms.include?(field)
      'Optional'
    end

    def load_schema_for(klass:)
      @schema = begin
                  if klass.respond_to?(:schema)
                    klass.new.singleton_class.schema || klass.schema
                  else
                    nil
                  end
                rescue
                  nil
                end
    end

    def load_required_terms_for(klass:)
      load_schema_for(klass: klass)
      begin
        if @schema.present?
          get_required_types(schema)
        else
          []
        end
      rescue
        []
      end
    end

    def uses_controlled_vocab?(field_name)
      @controlled_vocab_terms&.include?(field_name)
    end

    def load_controlled_vocab_terms_for(klass:)
      load_schema_for(klass: klass)
      controlled_properties = @schema.filter_map do |property|
                                next unless property.respond_to?(:meta)
                                sources = property.meta&.dig('controlled_values', 'sources')
                                next if sources.nil? || sources == ['null'] || sources == 'null'
                                property.name.to_s
                              end
      # if the schema didn't yield any controlled properties, fall back to registered vocabs
      return registered_controlled_vocab_fields if controlled_properties.empty?
      controlled_properties
    rescue
      []
    end

    def registered_controlled_vocab_fields
      qa_registry.filter_map do |k, v|
        k.singularize if v.klass == Qa::Authorities::Local::FileBasedAuthority
      end
    end

    def qa_registry
      @qa_registry ||= Qa::Authorities::Local.registry.instance_variable_get('@hash')
    end

    def get_required_types(schema)
      schema.select do |key|
        next false unless key.respond_to?(:meta) &&
                          key.meta["form"].is_a?(Hash) &&
                          key.meta["form"]["required"] == true
        true
      end.map(&:name).map(&:to_s)
    end

    def remove_empty_columns(rows, required_headings = [])
      return rows if rows.empty?

      # Transpose to work with columns
      columns = rows.transpose

      # Keep columns where heading is required OR has non-empty content
      non_empty_columns = columns.select.with_index do |column, index|
        heading = column[0] # Get the column heading from first row

        # Always keep everything in the required headings
        if @required_headings.include?(heading)
          true
        else
          # Check if any value after the header rows has content
          # Row 0: headers, Row 1: descriptions, Rows 2+: actual data
          column[2..-1].any? { |value| !value.nil? && value != "" && value != "---" }
        end
      end

      # Transpose back to rows
      non_empty_columns.transpose
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
