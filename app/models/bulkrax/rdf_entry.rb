# frozen_string_literal: true

require 'rdf'
module Bulkrax
  class RdfEntry < Entry
    serialize :raw_metadata, JSON

    def self.read_data(path)
      RDF::Reader.open(path)
    end

    def self.fields_from_data(data)
      data.predicates.map(&:to_s)
    end

    def self.data_for_entry(data)
      reader = data
      format = reader.class.format.to_sym
      collections = []
      children = []
      data = RDF::Writer.for(format).buffer do |writer|
        reader.each_statement do |statement|
          collections << statement.object.to_s if collection_field.present? && collection_field == statement.predicate.to_s
          children << statement.object.to_s if children_field.present? && children_field == statement.predicate.to_s
          writer << statement
        end
      end
      return {
        source_identifier: reader.subjects.first.to_s,
        format: format,
        data: data,
        collection: collections,
        children: children
      }
    end

    def self.collection_field
      Bulkrax.collection_field_mapping[self.to_s]
    end

    def self.children_field
      Bulkrax.parent_child_field_mapping[self.to_s]
    end

    def record
      @record ||= RDF::Reader.for(self.raw_metadata['format'].to_sym).new(self.raw_metadata['data'])
    end

    def build_metadata
      raise StandardError, 'Record not found' if record.nil?
      raise StandardError, 'Missing source identifier' if self.raw_metadata['source_identifier'].blank?

      self.parsed_metadata = {}
      self.parsed_metadata[Bulkrax.system_identifier_field] = [self.raw_metadata['source_identifier']]

      record.each_statement do |statement|
        # Only process the subject for our record (in case other data is in the file)
        next unless statement.subject.to_s == self.raw_metadata['source_identifier']
        add_metadata(statement.predicate.to_s, statement.object.to_s)
      end
      add_visibility
      add_rights_statement
      add_collections
      add_local
      self.parsed_metadata['file'] = self.raw_metadata['file']

      self.parsed_metadata
    end

    def collections_created?
      return true if self.raw_metadata['collection'].blank?
      self.raw_metadata['collection'].length == self.collection_ids.length
    end

    def find_or_create_collection_ids
      return self.collection_ids if collections_created?
      unless self.raw_metadata['collection'].blank?
        self.raw_metadata['collection'].each do |collection|
          c = find_collection(collection)
          self.collection_ids << c.id unless c.blank? || self.collection_ids.include?(c.id)
        end
      end
      return self.collection_ids
    end
  end
end
