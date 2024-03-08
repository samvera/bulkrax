# frozen_string_literal: true

module Bulkrax
  class OaiEntry < Entry
    serialize :raw_metadata, Bulkrax::NormalizedJson

    delegate :record, to: :raw_record

    # @api private
    #
    # Included to assist in testing; namely so that you can copy down an OAI entry, store it locally,
    # and then manually construct an {OAI::GetRecordResponse}.
    #
    # @see Bulkrax::EntrySpecHelper.oai_entry_for
    attr_writer :raw_record

    # @return [OAI::GetRecordResponse]
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
      self.raw_metadata = { record: record.metadata.to_s, header: record.header.to_s }

      # We need to establish the #factory_class before we proceed with the metadata.  See
      # https://github.com/samvera-labs/bulkrax/issues/702 for further details.
      #
      # tl;dr - if we don't have the right factory_class we might skip properties that are
      # specifically assigned to the factory class
      establish_factory_class
      add_metadata_from_record
      add_thumbnail_url

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

    # To ensure we capture the correct parse data, we first need to establish the factory_class.
    # @see https://github.com/samvera-labs/bulkrax/issues/702
    def establish_factory_class
      model_field_names = parser.model_field_mappings

      each_candidate_metadata_node do |node|
        next unless model_field_names.include?(node.name)
        add_metadata(node.name, node.content)
      end
    end

    def add_metadata_from_record
      each_candidate_metadata_node do |node|
        add_metadata(node.name, node.content)
      end
    end

    # A method that you could override to better handle the shape of the record's metadata.
    # @yieldparam node [Object<#name, #content>]
    def each_candidate_metadata_node
      record.metadata.children.each do |child|
        child.children.each do |node|
          yield(node)
        end
      end
    end

    def add_thumbnail_url
      add_metadata('thumbnail_url', thumbnail_url)
    end

    # Retrieve list of collections for the entry; add to collection_ids
    # If OAI-PMH doesn't return setSpec in the headers for GetRecord, use parser.collection_name
    #   in this case, if 'All' is selected, records will not be added to a collection.
    def find_collection_ids
      return self.collection_ids if defined?(@called_find_collection_ids)

      if sets.blank? || parser.collection_name != 'all'
        collection = find_collection(importerexporter.unique_collection_identifier(parser.collection_name))
        self.collection_ids << collection.id if collection.present? && !self.collection_ids.include?(collection.id)
      else # All - collections should exist for all sets
        sets.each do |set|
          c = find_collection(importerexporter.unique_collection_identifier(set.content))
          self.collection_ids << c.id if c.present? && !self.collection_ids.include?(c.id)
        end
      end

      @called_find_collection_ids = true
      return self.collection_ids
    end
  end
end
