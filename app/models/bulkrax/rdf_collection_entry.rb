# frozen_string_literal: true

module Bulkrax
  class RdfCollectionEntry < RdfEntry
    self.default_work_type = "Collection"
    def record
      @record ||= self.raw_metadata
    end

    def build_metadata
      self.parsed_metadata = self.raw_metadata
      add_local
      return self.parsed_metadata
    end
  end
end
