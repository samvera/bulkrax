# frozen_string_literal: true

## Generates sample CSV files showing Bulkrax field mappings for imports
# Helps users understand how to format their CSV files for Bulkrax imports.
#
# Example usage:
#   # Create CSV file on disk
#   Bulkrax::SampleCsvService.call(output: 'file', model_name: 'all')
#
#   # Get CSV string for download
#   csv_string = Bulkrax::SampleCsvService.call(output: 'csv_string', model_name: 'GenericWork')

module Bulkrax
  class SampleCsvService
    # Column groups with descriptions for the template
    COLUMN_DESCRIPTIONS = {
      highlighted: [
        { "work_type" => "The work types configured in your repository are listed below.\nIf left blank, your default work type, #{Bulkrax.default_work_type}, is used." },
        { "source_identifier" => "This must be a unique identifier.\nIt can be alphanumeric with some special charaters (e.g. hyphens, colons), and URLs are also supported." },
        { "id" => "This column would optionally be included only if it is a re-import, i.e. for updating or deleting records.\nThis is a key identifier used by the system, which you wouldn't have for new imports." },
        { "rights_statement" => "Rights statement URI for the work.\nIf not included, uses the value specified on the bulk import configuration screen." }
      ],
      visibility: [
        { "visibility" => "Uses the value specified on the bulk import configuration screen if not added here.\nValid options: open, institution, restricted, embargo, lease" },
        { "embargo_release_date" => "Required for embargo (yyyy-mm-dd)" },
        { "visibility_during_embargo" => "Required for embargo" },
        { "visibility_after_embargo" => "Required for embargo" },
        { "lease_expiration_date" => "Required for lease (yyyy-mm-dd)" },
        { "visibility_during_lease" => "Required for lease" },
        { "visibility_after_lease" => "Required for lease" }
      ],
      files: [
        { "file" => "Use filenames exactly matching those in your files folder.\nZip your CSV and files folder together and attach this to your importer." },
        { "remote_files" => "Use the URLs to remote files to be attached to the work." }
      ]
    }.freeze

    # Properties to exclude from CSV
    IGNORED_PROPERTIES = %w[
      admin_set_id alternate_ids arkivo_checksum
      bulkrax_identifier
      collection_type_gid contexts created_at
      date_modified date_uploaded depositor
      embargo embargo_id
      file_ids
      has_model head
      internal_resource is_child
      lease lease_id
      member_ids member_of_collection_ids modified_date
      new_record
      on_behalf_of owner proxy_depositor
      rendering_ids representative_id
      schema_version split_from_pdf_id state tail
      thumbnail_id
      updated_at
    ].freeze

    attr_reader :model_name, :mappings, :all_models

    def initialize(model_name: nil)
      @model_name = model_name
      @mappings = load_mappings
      @all_models = load_models(model_name)
      @field_list = []
    end

    def self.call(model_name: nil, output: 'file', **args)
      raise NameError, "Hyrax is not defined" unless defined?(::Hyrax)
      new(model_name: model_name).send("to_#{output}", **args)
    end

    def to_file(file_path: nil)
      file_path ||= default_file_path
      CSV.open(file_path, "w") { |csv| write_csv_rows(csv) }
      file_path
    end

    def to_csv_string
      CSV.generate { |csv| write_csv_rows(csv) }
    end

    def to_importer(file_path: nil)
      file_path ||= default_file_path
      to_file(file_path: file_path)
      create_importer(file_path)
    end

    private

    # Initialization helpers
    def load_mappings
      Bulkrax.field_mappings["Bulkrax::CsvParser"].reject do |_key, value|
        value["generated"] == true
      end
    end

    def load_models(model_name)
      case model_name
      when nil then []
      when 'all' then all_available_models
      else
        model_name.constantize ? [model_name] : []
      end
    rescue StandardError
      []
    end

    def all_available_models
      Hyrax.config.curation_concerns.map(&:name) +
        [Bulkrax.collection_model_class&.name, Bulkrax.file_model_class&.name].compact
    end

    # CSV generation
    def write_csv_rows(csv)
      csv_rows.each { |row| csv << row }
    end

    def csv_rows
      @header_row = fill_header_row # Changed from build_header_row to match spec
      rows = [
        @header_row,
        build_explanation_row,
        *build_model_rows
      ]
      remove_empty_columns(rows)
    end

    def fill_header_row # Renamed from build_header_row to match original method name
      column_groups = extract_column_groups
      @required_headings = column_groups[:core] + column_groups[:relationships] + column_groups[:files]

      merged_properties = collect_all_properties
      remaining = (merged_properties - column_groups.values.flatten).sort

      column_groups[:core] + column_groups[:relationships] +
        column_groups[:files] + remaining
    end

    def build_explanation_row
      property_explanations.map { |prop| prop.values.join(" ") }
    end

    def build_model_rows
      @all_models.map { |m| model_breakdown(m) } # Changed back to use model_breakdown
    end

    def model_breakdown(model_name) # Renamed from build_model_row to match original
      klass = determine_klass_for(model_name)
      return [] if klass.nil?

      field_list = find_or_create_field_list_for(model_name: model_name)
      @required_terms = field_list.dig(model_name, 'required_terms')

      @header_row.map do |column|
        determine_column_value(column, model_name, field_list)
      end
    end

    # Column value determination
    def determine_column_value(column, model_name, field_list)
      key = mapped_to_key(column)

      if field_list.dig(model_name, "properties")&.include?(key)
        mark_required_or_optional(field: key)
      elsif special_column?(column, key)
        special_column_value(column, key, model_name)
      else
        '---'
      end
    end

    def special_column?(column, key)
      key.in?(['model', 'work_type']) ||
        column.in?(extract_column_names(:visibility)) ||
        column == 'source_identifier' ||
        column == 'rights_statement' ||
        column.in?(relationship_properties) ||
        column.in?(file_terms)
    end

    def special_column_value(column, key, model_name)
      return determine_klass_for(model_name).to_s if key.in?(['model', 'work_type'])
      return 'Required' if column == 'source_identifier'
      return mark_required_or_optional(field: key) if column == 'rights_statement'
      'Optional'
    end

    # Column extraction helpers
    def extract_column_groups
      {
        core: extract_column_names(:highlighted) + extract_column_names(:visibility),
        relationships: relationship_properties,
        files: file_terms
      }
    end

    def extract_column_names(group)
      COLUMN_DESCRIPTIONS[group].map { |hash| hash.keys.first }
    end

    def file_terms
      @file_terms ||= COLUMN_DESCRIPTIONS[:files].flat_map do |property_hash|
        property_hash.keys.filter_map do |key|
          @mappings.dig(key, "from")&.first
        end
      end
    end

    def relationship_properties
      @relationship_properties ||= [
        find_mapping_by_flag("related_children_field_mapping", 'children'),
        find_mapping_by_flag("related_parents_field_mapping", 'parents')
      ]
    end

    def find_mapping_by_flag(field_name, default)
      @mappings.find { |_k, v| v[field_name] == true }&.first || default
    end

    # Property collection
    def collect_all_properties
      field_lists = @all_models.map { |m| find_or_create_field_list_for(model_name: m) }

      field_lists
        .flat_map { |item| item.values.flat_map { |config| config["properties"] || [] } }
        .uniq
        .map { |property| key_to_mapped_column(property) }
        .uniq - IGNORED_PROPERTIES
    end

    # Property explanations
    def property_explanations
      load_controlled_vocab_terms

      @header_row.map do |column|
        { column => build_property_explanation(column) }
      end
    end

    def build_property_explanation(column)
      mapping_key = mapped_to_key(column)

      components = [
        find_description_for(column),
        controlled_vocab_text(mapping_key),
        split_text_for(mapping_key)
      ].compact

      components.join("\n")
    end

    def find_description_for(column)
      COLUMN_DESCRIPTIONS.each_value do |group|
        prop = group.find { |hash| hash.key?(column) }
        return prop[column] if prop
      end

      return 'Contains the id or source_identifier of related objects.' if column.in?(relationship_properties)

      if column.in?(file_terms)
        key = mapped_to_key(column)
        file_prop = COLUMN_DESCRIPTIONS[:files].find { |hash| hash.key?(key) }
        return file_prop[key] if file_prop
      end

      nil
    end

    def controlled_vocab_text(field_name)
      uses_controlled_vocab?(field_name) ? 'This property uses a controlled vocabulary.' : nil
    end

    def split_text_for(mapping_key)
      return nil unless @mappings.dig(mapping_key, "split")
      format_split_text(@mappings[mapping_key]["split"])
    end

    # Field list management
    def find_or_create_field_list_for(model_name:)
      existing = @field_list.find { |entry| entry.key?(model_name) }
      return existing if existing.present?

      klass = determine_klass_for(model_name)
      return {} if klass.nil?

      model_entry = build_field_list_entry(model_name, klass)
      @field_list << model_entry
      model_entry
    end

    def build_field_list_entry(model_name, klass)
      {
        model_name => {
          'properties' => extract_properties(klass),
          'required_terms' => load_required_terms_for(klass: klass),
          'controlled_vocab_terms' => load_controlled_vocab_terms_for(klass: klass)
        }
      }
    end

    def extract_properties(klass)
      if klass.respond_to?(:schema)
        Bulkrax::ValkyrieObjectFactory.schema_properties(klass).map(&:to_s)
      else
        klass.properties.keys.map(&:to_s)
      end
    end

    # Schema loading
    def load_schema_for(klass:)
      @schema = (klass.new.singleton_class.schema || klass.schema if klass.respond_to?(:schema))
    rescue StandardError
      nil
    end

    def load_required_terms_for(klass:)
      schema = load_schema_for(klass: klass)
      return [] if schema.blank?

      get_required_types(schema)
    rescue StandardError
      []
    end

    def get_required_types(schema)
      schema.select do |field|
        field.respond_to?(:meta) &&
          field.meta["form"].is_a?(Hash) &&
          field.meta["form"]["required"] == true
      end.map(&:name).map(&:to_s)
    end

    # Controlled vocabulary
    def load_controlled_vocab_terms
      @controlled_vocab_terms = @field_list.flat_map do |hash|
        hash.values.flat_map { |data| data["controlled_vocab_terms"] || [] }
      end.uniq
    end

    def load_controlled_vocab_terms_for(klass:)
      schema = load_schema_for(klass: klass)
      return [] unless schema

      controlled_properties = extract_controlled_properties(schema)
      controlled_properties.empty? ? registered_controlled_vocab_fields : controlled_properties
    rescue StandardError
      []
    end

    def extract_controlled_properties(schema)
      schema.filter_map do |property|
        next unless property.respond_to?(:meta)
        sources = property.meta&.dig('controlled_values', 'sources')
        next if sources.nil? || sources == ['null'] || sources == 'null'
        property.name.to_s
      end
    end

    def registered_controlled_vocab_fields
      qa_registry.filter_map do |k, v|
        k.singularize if v.klass == Qa::Authorities::Local::FileBasedAuthority
      end
    end

    def qa_registry
      @qa_registry ||= Qa::Authorities::Local.registry.instance_variable_get('@hash')
    end

    def uses_controlled_vocab?(field_name)
      @controlled_vocab_terms&.include?(field_name)
    end

    # Mapping utilities
    def mapped_to_key(column_str)
      @mappings.find { |_k, v| v["from"].include?(column_str) }&.first || column_str
    end

    def key_to_mapped_column(key)
      @mappings.dig(key, "from")&.first || key
    end

    def mark_required_or_optional(field:)
      return 'Unknown' unless @required_terms
      @required_terms.include?(field) ? 'Required' : 'Optional'
    end

    # Split formatting
    def format_split_text(split_value)
      return "Property does not split." if split_value.nil? # Added back the original message

      if split_value == true
        parse_split_pattern(Bulkrax.multi_value_element_split_on.source)
      elsif split_value.is_a?(String)
        parse_split_pattern(split_value)
      else
        split_value
      end
    end

    def parse_split_pattern(pattern)
      chars = extract_split_characters(pattern)
      format_split_message(chars)
    end

    def extract_split_characters(pattern)
      if (match = pattern.match(/\[([^\]]+)\]/))
        match[1]
      elsif (single = pattern.match(/\\(.)/))
        single[1]
      else
        pattern
      end
    end

    def format_split_message(chars)
      formatted = chars.chars.then do |c|
        c.length > 1 ? "#{c[0..-2].join(', ')}, or #{c.last}" : c.first
      end
      "Split multiple values with #{formatted}"
    end

    # Column filtering
    def remove_empty_columns(rows)
      return rows if rows.empty?

      columns = rows.transpose
      non_empty_columns = columns.select { |col| keep_column?(col) }
      non_empty_columns.transpose
    end

    def keep_column?(column)
      heading = column[0]
      return true if @required_headings.include?(heading)

      # Check if any data row (after header and description) has content
      column[2..-1].any? { |value| !value.nil? && value != "" && value != "---" }
    end

    # Utility methods
    def determine_klass_for(model_name)
      if Bulkrax.config.object_factory == Bulkrax::ValkyrieObjectFactory
        Valkyrie.config.resource_class_resolver.call(model_name)
      else
        model_name.constantize
      end
    rescue StandardError
      nil
    end

    def default_file_path
      Rails.root.join('tmp', 'imports', "bulkrax_template_#{timestamp}.csv")
    end

    def timestamp
      Time.now.utc.strftime('%Y%m%d_%H%M%S')
    end

    def create_importer(file_path)
      Bulkrax::Importer.create(
        name: "Sample CSV #{Time.now.utc.to_date}",
        admin_set_id: Hyrax::AdminSetCreateService.find_or_create_default_admin_set.id,
        user_id: User.find_by(email: 'admin@example.com').id,
        frequency: 'PT0S',
        parser_klass: 'Bulkrax::CsvParser',
        parser_fields: importer_parser_fields(file_path)
      )
    end

    def importer_parser_fields(file_path)
      {
        'visibility' => 'open',
        'rights_statement' => '',
        'override_rights_statement' => '0',
        'file_style' => 'Specify a Path on the Server',
        'import_file_path' => file_path,
        'update_files' => false
      }
    end
  end
end
