# frozen_string_literal: true

module Bulkrax
  class CsvCollectionEntry < CsvEntry
    def factory_class
      Collection
    end

    def build_metadata
      self.parsed_metadata = {}
      self.parsed_metadata[work_identifier] = self.identifier
      record.each do |key, value|
        next if self.parser.collection_field_mapping.to_s == key_without_numbers(key)

        index = key[/\d+/].to_i - 1 if key[/\d+/].to_i != 0
        add_metadata(key_without_numbers(key), value, index)
      end
      add_collection_type_gid
      add_visibility
      add_rights_statement
      add_collections
      add_local

      self.parsed_metadata
    end

    def add_collection_type_gid
      return if self.parsed_metadata['collection_type_gid'].present?

      self.parsed_metadata['collection_type_gid'] = ::Hyrax::CollectionType.find_or_create_default_collection_type.gid
    end
  end
end
