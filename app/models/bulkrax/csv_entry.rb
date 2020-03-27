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

      # rubocop:disable Style/IfUnlessModifier
      if importerexporter.parser.required_elements?(record.keys) == false
        raise StandardError, "Missing required elements, required elements are: #{importerexporter.parser.required_elements.join(', ')}"
      end
      # rubocop:enable Style/IfUnlessModifier

      self.parsed_metadata = {}
      self.parsed_metadata[Bulkrax.system_identifier_field] = [record['source_identifier']]

      record.each do |key, value|
        next if key == 'collection'
        add_metadata(key, value)
      end

      # construct full file path
      self.parsed_metadata['file'] ||= []
      self.parsed_metadata['file'] = self.parsed_metadata['file'].select { |f| f.present? && f != '[]' }
      self.parsed_metadata['file'] = self.parsed_metadata['file'].map { |f| path_to_file(f.tr(' ', '_')) }

      add_visibility
      add_rights_statement
      add_collections
      add_local

      self.parsed_metadata
    end

    def build_export_metadata
      make_round_trippable
      self.parsed_metadata = {}
      self.parsed_metadata[id] = work.id
      self.parsed_metadata[self.source_identifier_field] = work.id
      self.parsed_metadata['model'] = work.has_model.first
      mapping.each do |key, value|
        next if Bulkrax.reserved_properties.include?(key) && !field_supported?(key)
        next unless work.respond_to?(key)
        data = work.send(key)
        if data.is_a?(ActiveTriples::Relation)
          self.parsed_metadata[key] = data.join('; ').to_s unless value[:excluded]
        else
          self.parsed_metadata[key] = data
        end
      end
      unless work.is_a?(Collection)
        self.parsed_metadata['file'] = work.file_sets.map { |fs| "#{work.id}/#{filename(fs)}" unless filename(fs).blank? }.compact.join('; ')
      end
      self.parsed_metadata
    end

    # In order for the existing exported work, to be updated by a re-import
    # we need a unique value in Bulkrax.system_identifier_field
    # add the existing work id to Bulkrax.system_identifier_field
    def make_round_trippable
      values = work.send("#{Bulkrax.system_identifier_field}").to_a
      values << work.id
      work.send("#{Bulkrax.system_identifier_field}=", values)
      work.save
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
      unless record[self.class.collection_field].blank?
        record[self.class.collection_field].split(/\s*[:;|]\s*/).each do |collection|
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
