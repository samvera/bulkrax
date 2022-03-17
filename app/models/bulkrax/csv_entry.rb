# frozen_string_literal: true

require 'csv'

module Bulkrax
  # TODO: We need to rework this class some to address the Metrics/ClassLength rubocop offense.
  # We do too much in these entry classes. We need to extract the common logic from the various
  # entry models into a module that can be shared between them.
  class CsvEntry < Entry # rubocop:disable Metrics/ClassLength
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
      ActiveSupport::Deprecation.warn(
        'Creating Collections using the collection_field_mapping will no longer be supported as of Bulkrax version 3.0.' \
        ' Please configure Bulkrax to use related_parents_field_mapping and related_children_field_mapping instead.'
      )
      # If a multi-line CSV data is passed, grab the first row
      data = data.first if data.is_a?(CSV::Table)
      # model has to be separated so that it doesn't get mistranslated by to_h
      raw_data = data.to_h
      raw_data[:model] = data[:model] if data[:model].present?
      # If the collection field mapping is not 'collection', add 'collection' - the parser needs it
      raw_data[:collection] = raw_data[collection_field.to_sym] if raw_data.keys.include?(collection_field.to_sym) && collection_field != 'collection'
      return raw_data
    end

    def build_metadata
      raise StandardError, 'Record not found' if record.nil?
      raise StandardError, "Missing required elements, missing element(s) are: #{importerexporter.parser.missing_elements(keys_without_numbers(record.keys)).join(', ')}" unless importerexporter.parser.required_elements?(keys_without_numbers(record.keys))

      self.parsed_metadata = {}
      add_identifier
      add_ingested_metadata
      add_visibility
      add_metadata_for_model
      add_rights_statement
      add_collections
      add_local

      self.parsed_metadata
    end

    def add_identifier
      self.parsed_metadata[work_identifier] = [record[source_identifier]]
    end

    def add_metadata_for_model
      if factory_class == Collection
        add_collection_type_gid
      elsif factory_class == FileSet
        add_path_to_file
        validate_presence_of_parent!
      else
        add_file unless importerexporter.metadata_only?
        add_admin_set_id
      end
    end

    def add_ingested_metadata
      ActiveSupport::Deprecation.warn(
        'Creating Collections using the collection_field_mapping will no longer be supported as of Bulkrax version 3.0.' \
        ' Please configure Bulkrax to use related_parents_field_mapping and related_children_field_mapping instead.'
      )
      # we do not want to sort the values in the record before adding the metadata.
      # if we do, the factory_class will be set to the default_work_type for all values that come before "model" or "work type"
      record.each do |key, value|
        next if self.parser.collection_field_mapping.to_s == key_without_numbers(key)

        index = key[/\d+/].to_i - 1 if key[/\d+/].to_i != 0
        add_metadata(key_without_numbers(key), value, index)
      end
    end

    def add_file
      self.parsed_metadata['file'] ||= []
      if record['file']&.is_a?(String)
        self.parsed_metadata['file'] = record['file'].split(/\s*[;|]\s*/)
      elsif record['file'].is_a?(Array)
        self.parsed_metadata['file'] = record['file']
      end
      self.parsed_metadata['file'] = self.parsed_metadata['file'].map do |f|
        next if f.blank?

        path_to_file(f.tr(' ', '_'))
      end.compact
    end

    def build_export_metadata
      # make_round_trippable
      self.parsed_metadata = {}
      self.parsed_metadata['id'] = hyrax_record.id
      self.parsed_metadata[source_identifier] = hyrax_record.send(work_identifier)
      self.parsed_metadata['model'] = hyrax_record.has_model.first
      build_file_set_metadata
      build_relationship_metadata
      build_mapping_metadata

      # TODO: fix the "send" parameter in the conditional below
      # currently it returns: "NoMethodError - undefined method 'bulkrax_identifier' for #<Collection:0x00007fbe6a3b4248>"
      if mapping['collection']&.[]('join')
        self.parsed_metadata['collection'] = hyrax_record.member_of_collection_ids.join('; ')
        #   self.parsed_metadata['collection'] = hyrax_record.member_of_collections.map { |c| c.send(work_identifier)&.first }.compact.uniq.join(';')
      else
        hyrax_record.member_of_collections.each_with_index do |collection, i|
          self.parsed_metadata["collection_#{i + 1}"] = collection.id
          #     self.parsed_metadata["collection_#{i + 1}"] = collection.send(work_identifier)&.first
        end
      end

      build_files unless hyrax_record.is_a?(Collection)
      self.parsed_metadata
    end

    def build_file_set_metadata
      return unless hyrax_record.file_set?

      file_mapping = mapping['file']&.[]('from')&.first
      if file_mapping.blank?
        msg = %(This parser (#{parser.class}) is missing a "file" field_mapping. Please add one in config/initializers/bulkrax.rb).strip
        raise ::StandardError, msg
      end

      parsed_metadata[file_mapping] = hyrax_record.files&.map(&:original_name)
    end

    def build_relationship_metadata
      # Includes all relationship methods for all exportable record types (works, Collections, FileSets)
      relationship_methods = {
        related_parents_parsed_mapping => %i[member_of_collection_ids member_of_work_ids in_work_ids],
        related_children_parsed_mapping => %i[member_collection_ids member_work_ids file_set_ids]
      }

      relationship_methods.each do |relationship_key, methods|
        next if relationship_key.blank?

        parsed_metadata[relationship_key] ||= []
        methods.each do |m|
          parsed_metadata[relationship_key] << hyrax_record.public_send(m) if hyrax_record.respond_to?(m)
        end
        parsed_metadata[relationship_key] = parsed_metadata[relationship_key].flatten.uniq
      end
    end

    def build_mapping_metadata
      mapping.each do |key, value|
        next if Bulkrax.reserved_properties.include?(key) && !field_supported?(key)
        next if key == "model"
        next if value['excluded']

        object_key = key if value.key?('object')
        next unless hyrax_record.respond_to?(key.to_s) || object_key.present?

        if object_key.present?
          build_object(value)
        else
          build_value(key, value)
        end
      end
    end

    def build_object(value)
      data = hyrax_record.send(value['object'])
      return if data.empty?

      data = data.to_a if data.is_a?(ActiveTriples::Relation)
      object_metadata(Array.wrap(data))
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

    def object_metadata(data)
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

    def possible_collection_ids
      ActiveSupport::Deprecation.warn(
        'Creating Collections using the collection_field_mapping will no longer be supported as of Bulkrax version 3.0.' \
        ' Please configure Bulkrax to use related_parents_field_mapping and related_children_field_mapping instead.'
      )
      return @possible_collection_ids if @possible_collection_ids.present?

      collection_field_mapping = self.class.collection_field
      return [] unless collection_field_mapping.present? && record[collection_field_mapping].present?

      identifiers = []
      split_titles = record[collection_field_mapping].split(/\s*[;|]\s*/)
      split_titles.each do |c_title|
        matching_collection_entries = importerexporter.entries.select { |e| e.raw_metadata['title'] == c_title }
        raise ::StandardError, 'Only expected to find one matching entry' if matching_collection_entries.count > 1
        identifiers << matching_collection_entries.first&.identifier
      end
      @possible_collection_ids = identifiers.compact.presence || []
    end

    def collections_created?
      possible_collection_ids.length == self.collection_ids.length
    end

    def find_collection_ids
      return self.collection_ids if collections_created?
      if possible_collection_ids.present?
        possible_collection_ids.each do |collection_id|
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
  end
end
