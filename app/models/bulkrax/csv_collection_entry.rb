# frozen_string_literal: true

module Bulkrax
  class CsvCollectionEntry < CsvEntry
    # TODO: Similar to the has_model_ssim conundrum; we want to ask for the
    # collection_model_class_type.â
    self.default_work_type = "Collection"

    # Use identifier set by CsvParser#unique_collection_identifier, which falls back
    # on the Collection's first title if record[source_identifier] is not present
    def add_identifier
      self.parsed_metadata[work_identifier] = [self.identifier].flatten
    end

    def add_collection_type_gid
      return if self.parsed_metadata['collection_type_gid'].present?

      self.parsed_metadata['collection_type_gid'] = ::Hyrax::CollectionType.find_or_create_default_collection_type.to_global_id.to_s
    end
  end
end
