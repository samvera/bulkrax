# frozen_string_literal: true

require 'csv'

module Bulkrax
  class CsvEntry < Entry
    serialize :raw_metadata, JSON

    def self.fields_from_data(data)
      data.headers.flatten.compact.uniq
    end

    # there's a risk that this reads the whole file into memory and could cause a memory leak
    def self.read_data(path)
      raise StandardError, 'CSV path empty' if path.blank?
      CSV.read(path,
        headers: true,
        header_converters: :symbol,
        encoding: 'utf-8')
    end

    def self.data_for_entry(data, _source_id)
      # If a multi-line CSV data is passed, grab the first row
      data = data.first if data.is_a?(CSV::Table)
      # model has to be separated so that it doesn't get mistranslated by to_h
      raw_data = data.to_h
      raw_data[:model] = data[:model]
      # If the collection field mapping is not 'collection', add 'collection' - the parser needs it
      raw_data[:collection] = raw_data[collection_field.to_sym] if raw_data.keys.include?(collection_field.to_sym) && collection_field != 'collection'
      # If the children field mapping is not 'children', add 'children' - the parser needs it
      raw_data[:children] = raw_data[collection_field.to_sym] if raw_data.keys.include?(children_field.to_sym) && children_field != 'children'
      return raw_data
    end

    def self.collection_field
      Bulkrax.collection_field_mapping[self.class.to_s] || 'collection'
    end

    def self.children_field
      Bulkrax.parent_child_field_mapping[self.to_s] || 'children'
    end

    def build_metadata
      raise StandardError, 'Record not found' if record.nil?
      raise StandardError, "Missing required elements, missing element(s) are: #{importerexporter.parser.missing_elements(keys_without_numbers(record.keys)).join(', ')}" unless importerexporter.parser.required_elements?(keys_without_numbers(record.keys))

      self.parsed_metadata = {}
      self.parsed_metadata[work_identifier] = [record[source_identifier]]
      record.each do |key, value|
        next if key == 'collection'

        index = key[/\d+/].to_i - 1 if key[/\d+/].to_i != 0
        add_metadata(key_without_numbers(key), value, index)
      end
      add_file unless importerexporter.parser.parser_fields['metadata_only'] == true
      add_visibility
      add_rights_statement
      add_admin_set_id
      add_collections
      add_local
      self.parsed_metadata
    end

    def add_file
      self.parsed_metadata['file'] ||= []
      if record['file']&.is_a?(String)
        self.parsed_metadata['file'] = record['file'].split(/\s*[;|]\s*/)
      elsif record['file'].is_a?(Array)
        self.parsed_metadata['file'] = record['file']
      end
      self.parsed_metadata['file'] = self.parsed_metadata['file'].map { |f| path_to_file(f.tr(' ', '_')) }
    end

    def build_export_metadata
      # make_round_trippable
      self.parsed_metadata = {}
      self.parsed_metadata['id'] = hyrax_record.id
      self.parsed_metadata[source_identifier] = hyrax_record.send(work_identifier)
      self.parsed_metadata['model'] = hyrax_record.has_model.first
      build_mapping_metadata
      if mapping['collections']&.[]('join')
        self.parsed_metadata['collections'] = hyrax_record.member_of_collection_ids.join('; ')
      else
        hyrax_record.member_of_collection_ids.each_with_index do |collection_id, i|
          self.parsed_metadata["collections_#{i + 1}"] = collection_id
        end
      end
      build_files unless hyrax_record.is_a?(Collection)
      self.parsed_metadata
    end

    def build_mapping_metadata
      mapping.each do |key, value|
        next if Bulkrax.reserved_properties.include?(key) && !field_supported?(key)
        next if key == "model"
        next if value['excluded']

        object_key = key if value.key?('object')
        next unless hyrax_record.respond_to?(key.to_s) || object_key.present?

        if object_key.present?
          build_object(object_key, value)
        else
          build_value(key, value)
        end
      end
    end

    def build_object(object_key, value)
      data = hyrax_record.send(value['object'])
      return if data.empty?

      data = data.to_a if data.is_a?(ActiveTriples::Relation)
      object_metadata(Array.wrap(data), object_key)
    end

    def build_value(key, value)
      data = hyrax_record.send(key.to_s)
      if data.is_a?(ActiveTriples::Relation)
        if value['join']
          self.parsed_metadata[key_for_export(key)] = data.map { |d| prepare_export_data(d) }.join('; ').to_s
        else
          data.each_with_index do |d, i|
            self.parsed_metadata["#{key_for_export(key)}_#{i + 1}"] = prepare_export_data(d)
          end
        end
      else
        self.parsed_metadata[key_for_export(key)] = prepare_export_data(data)
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

    def prepare_export_data(datum)
      if datum.is_a?(ActiveTriples::Resource)
        datum.to_uri.to_s
      else
        datum
      end
    end

    def object_metadata(data, object_key)
      data = data.map { |d| eval(d) }.flatten # rubocop:disable Security/Eval

      data.each_with_index do |obj, index|
        # allow the object_key to be valid whether it's a string or symbol
        obj = obj.with_indifferent_access

        next unless obj[object_key]
        if obj[object_key].is_a?(Array)
          obj[object_key].each_with_index do |_nested_item, nested_index|
            self.parsed_metadata["#{key_for_export(object_key)}_#{index + 1}_#{nested_index + 1}"] = prepare_export_data(obj[object_key][nested_index])
          end
        else
          self.parsed_metadata["#{key_for_export(object_key)}_#{index + 1}"] = prepare_export_data(obj[object_key])
        end
      end
    end

    def build_files
      if mapping['file']&.[]('join')
        self.parsed_metadata['file'] = hyrax_record.file_sets.map { |fs| filename(fs).to_s if filename(fs).present? }.compact.join('; ')
      else
        hyrax_record.file_sets.each_with_index do |fs, i|
          self.parsed_metadata["file_#{i + 1}"] = filename(fs).to_s if filename(fs).present?
        end
      end
    end

    # In order for the existing exported hyrax_record, to be updated by a re-import
    # we need a unique value in system_identifier
    # add the existing hyrax_record id to system_identifier
    def make_round_trippable
      values = hyrax_record.send(work_identifier.to_s).to_a
      values << hyrax_record.id
      hyrax_record.send("#{work_identifier}=", values)
      hyrax_record.save
    end

    def record
      @record ||= raw_metadata
    end

    def self.matcher_class
      Bulkrax::CsvMatcher
    end

    def collections_created?
      return true if record[self.class.collection_field].blank?
      record[self.class.collection_field].split(/\s*[:;|]\s*/).length == self.collection_ids.length
    end

    def find_or_create_collection_ids
      return self.collection_ids if collections_created?
      valid_system_id(Collection)
      if record[self.class.collection_field].present?
        record[self.class.collection_field].split(/\s*[:;|]\s*/).each do |collection|
          c = find_collection(collection)
          self.collection_ids << c.id unless c.blank? || self.collection_ids.include?(c.id)
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
  end
end
