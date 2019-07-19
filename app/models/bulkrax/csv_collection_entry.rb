module Bulkrax
  class CsvCollectionEntry < CsvEntry
    def factory_class
      Collection
    end

    def build_metadata
      self.parsed_metadata = self.raw_metadata
    end

    def collections_created?
      true
    end
  end
end
