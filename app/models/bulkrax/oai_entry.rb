# frozen_string_literal: true

require 'erb'
require 'ostruct'

module Bulkrax
  class OaiEntry < Entry
    serialize :raw_metadata, JSON

    delegate :record, to: :raw_record

    def raw_record
      @raw_record ||= client.get_record(identifier: identifier, metadata_prefix: parser.parser_fields['metadata_prefix'])
    end

    def sets
      record.header.set_spec
    end

    def context
      @context ||= OpenStruct.new(record: record, identifier: record.header.identifier)
    end

    def thumbnail_url
      ERB.new(parser.parser_fields['thumbnail_url']).result(context.instance_eval { binding })
    end

    def build_metadata
      self.parsed_metadata = {}
      self.parsed_metadata[work_identifier] = [record.header.identifier]

      record.metadata.children.each do |child|
        child.children.each do |node|
          add_metadata(node.name, node.content)
        end
      end
      add_metadata('thumbnail_url', thumbnail_url)

      add_visibility
      add_rights_statement
      add_admin_set_id
      add_collections
      add_local

      return self.parsed_metadata
    end

    def collections_created?
      if parser.collection_name == 'all'
        sets.blank? || (sets.present? && sets.size == self.collection_ids.size)
      else
        self.collection_ids.size == 1
      end
    end

    # Retrieve list of collections for the entry; add to collection_ids
    # If OAI-PMH doesn't return setSpec in the headers for GetRecord, use parser.collection_name
    #   in this case, if 'All' is selected, records will not be added to a collection.
    def find_or_create_collection_ids
      return self.collection_ids if collections_created?

      if sets.blank? || parser.collection_name != 'all'
        # c = Collection.where(Bulkrax.system_identifier_field => importerexporter.unique_collection_identifier(parser.collection_name)).first
        c = find_collection(importerexporter.unique_collection_identifier(parser.collection_name))
        self.collection_ids << c.id if c.present? && !self.collection_ids.include?(c.id)
      else # All - collections should exist for all sets
        sets.each do |set|
          c = Collection.find_by(work_identifier => importerexporter.unique_collection_identifier(set.content))
          self.collection_ids << c.id if c.present? && !self.collection_ids.include?(c.id)
        end
      end
      return self.collection_ids
    end
  end
end
