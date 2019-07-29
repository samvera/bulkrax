require 'language_list'
require 'erb'
require 'ostruct'

module Bulkrax
  class OaiEntry < Entry
    def raw_record
      @raw_record ||= client.get_record(identifier: identifier, metadata_prefix: parser.parser_fields['metadata_prefix'])
    end

    def record
      raw_record.record
    end

    def sets
      raw_record.record.header.set_spec
    end

    def contributing_institution
      parser.parser_fields['institution_name']
    end

    def context
      @context ||= OpenStruct.new(record: record, identifier: record.header.identifier)
    end

    def thumbnail_url
      ERB.new(parser.parser_fields['thumbnail_url']).result(context.instance_eval { binding })
    end

    def build_metadata
      self.parsed_metadata = {}
      self.parsed_metadata[Bulkrax.system_identifier_field] = [record.header.identifier]

      record.metadata.children.each do |child|
        child.children.each do |node|
          add_metadata(node.name, node.content)
        end
      end
      add_metadata('thumbnail_url', thumbnail_url)

      self.parsed_metadata['contributing_institution'] = [contributing_institution]

      add_visibility
      add_rights_statement
      add_collections

      return self.parsed_metadata
    end

    def collections_created?
      if sets.blank? || parser.collection_name != 'all'
        self.collection_ids.length == 1
      else
        sets.length == self.collection_ids.length  
      end
    end

    # Retrieve list of collections for the entry; add to collection_ids
    # If OAI-PMH doesn't return setSpec in the headers for GetRecord, use parser.collection_name
    #   in this case, if 'All' is selected, records will not be added to a collection.
    def find_or_create_collection_ids
      return self.collection_ids if collections_created?

      if sets.blank?
        c = Collection.where(Bulkrax.system_identifier_field => parser.collection_name).first
        self.collection_ids << c.id unless c.blank? || self.collection_ids.include?(c.id)
      else
        sets.each do |set|
          c = Collection.where(Bulkrax.system_identifier_field => set.content).first
          self.collection_ids << c.id unless c.blank? || self.collection_ids.include?(c.id)
        end
      end
      
      return self.collection_ids
    end

  end
end
