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
      CSV.read(path,
               headers: true,
               header_converters: :symbol,
               encoding: 'utf-8')
    end

    def self.data_for_entry(data)
      # If a multi-line CSV data is passed, grab the first row
      data = data.first if data.is_a?(CSV::Table)
      raw_data = data.to_h
      # If the collection field mapping is not 'collection', add 'collection' - the parser needs it
      raw_data[:collection] = raw_data[collection_field.to_sym] if raw_data.keys.include?(collection_field.to_sym) && collection_field != 'collection'
      # If the children field mapping is not 'children', add 'children' - the parser needs it
      raw_data[:children] = raw_data[collection_field.to_sym] if raw_data.keys.include?(children_field.to_sym) && children_field != 'children'
      return raw_data
    end

    def self.source_identifier_field
      Bulkrax.source_identifier_field_mapping[self.to_s] || 'source_identifier'
    end

    def self.collection_field
      Bulkrax.collection_field_mapping[self.class.to_s] || 'collection'
    end

    def self.children_field
      Bulkrax.parent_child_field_mapping[self.to_s] || 'children'
    end

    def build_metadata
      raise StandardError, 'Record not found' if record.nil?

      raise StandardError, "Missing required elements, required elements are: #{importerexporter.parser.required_elements.join(', ')}" unless importerexporter.parser.required_elements?(record.keys)

      self.parsed_metadata = {}
      self.parsed_metadata[Bulkrax.system_identifier_field] = [record['source_identifier']]

      record.each do |key, value|
        next if key == 'collection'
        add_metadata(key, value)
      end

      add_file
      add_visibility
      add_rights_statement
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
      make_round_trippable
      self.parsed_metadata = {}
      self.parsed_metadata['id'] = hyrax_record.id
      self.parsed_metadata[self.class.source_identifier_field] = hyrax_record.id
      self.parsed_metadata['model'] = hyrax_record.has_model.first
      mapping.each do |key, value|
        next if Bulkrax.reserved_properties.include?(key) && !field_supported?(key)
        next unless hyrax_record.respond_to?(key)
        data = hyrax_record.send(key)
        if data.is_a?(ActiveTriples::Relation)
          self.parsed_metadata[key] = data.map { |d| prepare_export_data(d) }.join('; ').to_s unless value[:excluded]
        else
          self.parsed_metadata[key] = prepare_export_data(data)
        end
      end
      unless hyrax_record.is_a?(Collection)
        self.parsed_metadata['file'] = hyrax_record.file_sets.map { |fs| filename(fs).to_s unless filename(fs).blank? }.compact.join('; ')
      end
      self.parsed_metadata
    end

    def prepare_export_data(datum)
      if datum.is_a?(ActiveTriples::Resource)
        datum.to_uri.to_s
      else
        datum
      end
    end

    # In order for the existing exported hyrax_record, to be updated by a re-import
    # we need a unique value in Bulkrax.system_identifier_field
    # add the existing hyrax_record id to Bulkrax.system_identifier_field
    def make_round_trippable
      values = hyrax_record.send(Bulkrax.system_identifier_field.to_s).to_a
      values << hyrax_record.id
      hyrax_record.send("#{Bulkrax.system_identifier_field}=", values)
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
      record[self.class.collection_field].split(/\s*[;|]\s*/).length == self.collection_ids.length
    end

    def find_or_create_collection_ids
      return self.collection_ids if collections_created?
      valid_system_id(Collection)
      unless record[self.class.collection_field].blank?
        record[self.class.collection_field].split(/\s*[;|]\s*/).each do |collection|
          c = find_collection(collection)
          self.collection_ids << c.id unless c.blank? || self.collection_ids.include?(c.id)
        end
      end
      return self.collection_ids
    end

    def required_elements?(keys)
      !required_elements.map { |el| keys.include?(el) }.include?(false)
    end

    def required_elements
      %w[title source_identifier]
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
