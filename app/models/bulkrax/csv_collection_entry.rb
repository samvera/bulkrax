# frozen_string_literal: true

module Bulkrax
  class CsvCollectionEntry < CsvEntry
    def factory_class
      Collection
    end

    # Use identifier set by CsvParser#unique_collection_identifier, which falls back
    # on the Collection's first title if record[source_identifier] is not present
    def add_identifier
      self.parsed_metadata[work_identifier] = [self.identifier]
    end

    def add_collection_type_gid
      return if self.parsed_metadata['collection_type_gid'].present?

      self.parsed_metadata['collection_type_gid'] = ::Hyrax::CollectionType.find_or_create_default_collection_type.gid
    end
  end
end
