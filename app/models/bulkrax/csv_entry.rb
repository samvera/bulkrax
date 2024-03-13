# frozen_string_literal: true

module Bulkrax
  # TODO: We need to rework this class some to address the Metrics/ClassLength rubocop offense.
  # We do too much in these entry classes. We need to extract the common logic from the various
  # entry models into a module that can be shared between them.
  class CsvEntry < Entry # rubocop:disable Metrics/ClassLength
    serialize :raw_metadata, Bulkrax::NormalizedJson

    def self.fields_from_data(data)
      data.headers.flatten.compact.uniq
    end

    class_attribute(:csv_read_data_options, default: {})

    # there's a risk that this reads the whole file into memory and could cause a memory leak
    # we strip any special characters out of the headers. looking at you Excel
    def self.read_data(path)
      raise StandardError, 'CSV path empty' if path.blank?
      options = {
        headers: true,
        header_converters: ->(h) { h.to_s.gsub(/[^\w\d\. -]+/, '').strip.to_sym },
        encoding: 'utf-8'
      }.merge(csv_read_data_options)

      results = CSV.read(path, **options)
      csv_wrapper_class.new(results)
    end

    # The purpose of this class is to reject empty lines.  This causes lots of grief in importing.
    # But why not use {CSV.read}'s `skip_lines` option?  Because for some CSVs, it will never finish
    # reading the file.
    #
    # There is a spec that demonstrates this approach works.
    class CsvWrapper
      include Enumerable
      def initialize(original)
        @original = original
      end

      delegate :headers, to: :@original

      def each
        @original.each do |row|
          next if all_fields_are_empty_for(row: row)
          yield(row)
        end
      end

      private

      def all_fields_are_empty_for(row:)
        row.to_hash.values.all?(&:blank?)
      end
    end
    class_attribute :csv_wrapper_class, default: CsvWrapper

    def self.data_for_entry(data, _source_id, parser)
      # If a multi-line CSV data is passed, grab the first row
      data = data.first if data.is_a?(CSV::Table)
      # model has to be separated so that it doesn't get mistranslated by to_h
      raw_data = data.to_h
      raw_data[:model] = data[:model] if data[:model].present?
      # If the collection field mapping is not 'collection', add 'collection' - the parser needs it
      # TODO: change to :parents
      raw_data[:parents] = raw_data[parent_field(parser).to_sym] if raw_data.keys.include?(parent_field(parser).to_sym) && parent_field(parser) != 'parents'
      return raw_data
    end

    def build_metadata
      validate_record

      self.parsed_metadata = {}
      add_identifier
      establish_factory_class
      add_ingested_metadata
      # TODO(alishaevn): remove the collections stuff entirely and only reference collections via the new parents code
      add_collections
      add_visibility
      add_metadata_for_model
      add_rights_statement
      sanitize_controlled_uri_values!
      add_local

      self.parsed_metadata
    end

    def validate_record
      raise StandardError, 'Record not found' if record.nil?
      unless importerexporter.parser.required_elements?(record)
        raise StandardError, "Missing required elements, missing element(s) are: "\
"#{importerexporter.parser.missing_elements(record).join(', ')}"
      end
    end

    def add_identifier
      self.parsed_metadata[work_identifier] = [record[source_identifier]]
    end

    def establish_factory_class
      parser.model_field_mappings.each do |key|
        add_metadata('model', record[key]) if record.key?(key)
      end
    end

    def add_metadata_for_model
      if factory_class.present? && factory_class == Bulkrax.collection_model_class
        add_collection_type_gid if defined?(::Hyrax)
        # add any additional collection metadata methods here
      elsif factory_class == Bulkrax.file_model_class
        validate_presence_of_filename!
        add_path_to_file
        validate_presence_of_parent!
      else
        add_file unless importerexporter.metadata_only?
        add_admin_set_id
      end
    end

    def add_ingested_metadata
      # we do not want to sort the values in the record before adding the metadata.
      # if we do, the factory_class will be set to the default_work_type for all values that come before "model" or "work type"
      record.each do |key, value|
        index = key[/\d+/].to_i - 1 if key[/\d+/].to_i != 0
        add_metadata(key_without_numbers(key), value, index)
      end
    end

    def add_file
      self.parsed_metadata['file'] ||= []
      if record['file']&.is_a?(String)
        self.parsed_metadata['file'] = record['file'].split(Bulkrax.multi_value_element_split_on)
      elsif record['file'].is_a?(Array)
        self.parsed_metadata['file'] = record['file']
      end
      self.parsed_metadata['file'] = self.parsed_metadata['file'].map do |f|
        next if f.blank?

        path_to_file(f.tr(' ', '_'))
      end.compact
    end

    def build_export_metadata
      self.parsed_metadata = {}

      build_system_metadata
      build_files_metadata if Bulkrax.collection_model_class.present? && !hyrax_record.is_a?(Bulkrax.collection_model_class)
      build_relationship_metadata
      build_mapping_metadata
      self.save!

      self.parsed_metadata
    end

    # Metadata required by Bulkrax for round-tripping
    def build_system_metadata
      self.parsed_metadata['id'] = hyrax_record.id
      source_id = hyrax_record.send(work_identifier)
      # Because ActiveTriples::Relation does not respond to #to_ary we can't rely on Array.wrap universally
      source_id = source_id.to_a if source_id.is_a?(ActiveTriples::Relation)
      source_id = Array.wrap(source_id).first
      self.parsed_metadata[source_identifier] = source_id
      model_name = hyrax_record.respond_to?(:to_rdf_representation) ? hyrax_record.to_rdf_representation : hyrax_record.has_model.first
      self.parsed_metadata[key_for_export('model')] = model_name
    end

    def build_files_metadata
      # attaching files to the FileSet row only so we don't have duplicates when importing to a new tenant
      if hyrax_record.work?
        build_thumbnail_files
      else
        file_mapping = key_for_export('file')
        file_sets = hyrax_record.file_set? ? Array.wrap(hyrax_record) : hyrax_record.file_sets
        filenames = map_file_sets(file_sets)

        handle_join_on_export(file_mapping, filenames, mapping['file']&.[]('join')&.present?)
      end
    end

    def build_relationship_metadata
      # Includes all relationship methods for all exportable record types (works, Collections, FileSets)
      relationship_methods = {
        related_parents_parsed_mapping => %i[member_of_collection_ids member_of_work_ids in_work_ids],
        related_children_parsed_mapping => %i[member_collection_ids member_work_ids file_set_ids]
      }

      relationship_methods.each do |relationship_key, methods|
        next if relationship_key.blank?

        values = []
        methods.each do |m|
          values << hyrax_record.public_send(m) if hyrax_record.respond_to?(m)
        end
        values = values.flatten.uniq
        next if values.blank?

        handle_join_on_export(relationship_key, values, mapping[related_parents_parsed_mapping]['join'].present?)
      end
    end

    # The purpose of this helper module is to make easier the testing of the rather complex
    # switching logic for determining the method we use for building the value.
    module AttributeBuilderMethod
      # @param key [Symbol]
      # @param value [Hash<String, Object>]
      # @param entry [Bulkrax::Entry]
      #
      # @return [NilClass] when we won't be processing this field
      # @return [Symbol] (either :build_value or :build_object)
      def self.for(key:, value:, entry:)
        return if key == 'model'
        return if key == 'file'
        return if key == entry.related_parents_parsed_mapping
        return if key == entry.related_children_parsed_mapping
        return if value['excluded'] || value[:excluded]
        return if Bulkrax.reserved_properties.include?(key) && !entry.field_supported?(key)

        object_key = key if value.key?('object') || value.key?(:object)
        return unless entry.hyrax_record.respond_to?(key.to_s) || object_key.present?

        models_to_skip = Array.wrap(value['skip_object_for_model_names'] || value[:skip_object_for_model_names] || [])

        return :build_value if models_to_skip.detect { |model| entry.factory_class.model_name.name == model }
        return :build_object if object_key.present?

        :build_value
      end
    end

    def build_mapping_metadata
      mapping = fetch_field_mapping
      mapping.each do |key, value|
        method_name = AttributeBuilderMethod.for(key: key, value: value, entry: self)
        next unless method_name

        send(method_name, key, value)
      end
    end

    def build_object(_key, value)
      return unless hyrax_record.respond_to?(value['object'])

      data = hyrax_record.send(value['object'])
      return if data.empty?

      data = data.to_a if data.is_a?(ActiveTriples::Relation)
      object_metadata(Array.wrap(data))
    end

    def build_value(property_name, mapping_config)
      return unless hyrax_record.respond_to?(property_name.to_s)

      data = hyrax_record.send(property_name.to_s)

      if mapping_config['join'] || !data.is_a?(Enumerable)
        self.parsed_metadata[key_for_export(property_name)] = prepare_export_data_with_join(data)
      else
        data.each_with_index do |d, i|
          self.parsed_metadata["#{key_for_export(property_name)}_#{i + 1}"] = prepare_export_data(d)
        end
      end
    end

    # On export the key becomes the from and the from becomes the destination. It is the opposite of the import because we are moving data the opposite direction
    # metadata that does not have a specific Bulkrax entry is mapped to the key name, as matching keys coming in are mapped by the csv parser automatically
    def key_for_export(key)
      clean_key = key_without_numbers(key)
      unnumbered_key = mapping[clean_key] ? mapping[clean_key]['from'].first : clean_key
      # Bring the number back if there is one
      "#{unnumbered_key}#{key.sub(clean_key, '')}"
    end

    def prepare_export_data_with_join(data)
      # Yes...it's possible we're asking to coerce a multi-value but only have a single value.
      return data.to_s unless data.is_a?(Enumerable)
      return "" if data.empty?

      data.map { |d| prepare_export_data(d) }.join(Bulkrax.multi_value_element_join_on).to_s
    end

    def prepare_export_data(datum)
      if datum.is_a?(ActiveTriples::Resource)
        datum.to_uri.to_s
      else
        datum
      end
    end

    def object_metadata(data)
      # NOTE: What is `d` in this case:
      #
      #  "[{\"single_object_first_name\"=>\"Fake\", \"single_object_last_name\"=>\"Fakerson\", \"single_object_position\"=>\"Leader, Jester, Queen\", \"single_object_language\"=>\"english\"}]"
      #
      # The above is a stringified version of a Ruby string.  Using eval is a very bad idea as it
      # will execute the value of `d` within the full Ruby interpreter context.
      #
      # TODO: Would it be possible to store this as a non-string?  Maybe the actual Ruby Array and Hash?
      data = data.map { |d| eval(d) }.flatten # rubocop:disable Security/Eval

      data.each_with_index do |obj, index|
        next if obj.nil?
        # allow the object_key to be valid whether it's a string or symbol
        obj = obj.with_indifferent_access

        obj.each_key do |key|
          if obj[key].is_a?(Array)
            obj[key].each_with_index do |_nested_item, nested_index|
              self.parsed_metadata["#{key_for_export(key)}_#{index + 1}_#{nested_index + 1}"] = prepare_export_data(obj[key][nested_index])
            end
          else
            self.parsed_metadata["#{key_for_export(key)}_#{index + 1}"] = prepare_export_data(obj[key])
          end
        end
      end
    end

    def build_thumbnail_files
      return unless importerexporter.include_thumbnails

      thumbnail_mapping = 'thumbnail_file'
      file_sets = Array.wrap(hyrax_record.thumbnail)

      filenames = map_file_sets(file_sets)
      handle_join_on_export(thumbnail_mapping, filenames, false)
    end

    def handle_join_on_export(key, values, join)
      if join
        parsed_metadata[key] = values.join(Bulkrax.multi_value_element_join_on)
      else
        values.each_with_index do |value, i|
          parsed_metadata["#{key}_#{i + 1}"] = value
        end
        parsed_metadata.delete(key)
      end
    end

    def record
      @record ||= raw_metadata
    end

    def self.matcher_class
      Bulkrax::CsvMatcher
    end

    def collection_identifiers
      return @collection_identifiers if @collection_identifiers.present?

      parent_field_mapping = self.class.parent_field(parser)
      return [] unless parent_field_mapping.present? && record[parent_field_mapping].present?

      identifiers = []
      split_references = record[parent_field_mapping].split(Bulkrax.multi_value_element_split_on)
      split_references.each do |c_reference|
        matching_collection_entries = importerexporter.entries.select do |e|
          (e.raw_metadata&.[](source_identifier) == c_reference) &&
            e.is_a?(CsvCollectionEntry)
        end
        raise ::StandardError, 'Only expected to find one matching entry' if matching_collection_entries.count > 1
        identifiers << matching_collection_entries.first&.identifier
      end
      @collection_identifiers = identifiers.compact.presence || []
    end

    def collections_created?
      # TODO: look into if this method is still needed after new relationships code
      true
    end

    def find_collection_ids
      return self.collection_ids if collections_created?
      if collection_identifiers.present?
        collection_identifiers.each do |collection_id|
          c = find_collection(collection_id)
          skip = c.blank? || self.collection_ids.include?(c.id)
          self.collection_ids << c.id unless skip
        end
      end

      self.collection_ids
    end

    # If only filename is given, construct the path (/files/my_file)
    def path_to_file(file)
      # return if we already have the full file path
      return file if File.exist?(file)
      path = importerexporter.parser.path_to_files
      f = File.join(path, file)
      return f if File.exist?(f)
      raise "File #{f} does not exist"
    end

    private

    def map_file_sets(file_sets)
      file_sets.map { |fs| filename(fs).to_s if filename(fs).present? }.compact
    end
  end
end
