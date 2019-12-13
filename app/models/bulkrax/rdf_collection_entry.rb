# frozen_string_literal: true

module Bulkrax
  class RdfCollectionEntry < RdfEntry
    def record
      @record ||= self.raw_metadata
    end

    def build_metadata
      self.parsed_metadata = self.raw_metadata
      add_local
      return self.parsed_metadata
    end

    def factory_class
      Collection
    end
  end
end
