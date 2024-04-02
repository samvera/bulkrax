# frozen_string_literal: true

module Bulkrax
  class OaiSetEntry < OaiEntry
    self.default_work_type = Bulkrax.collection_model_class.to_s

    def build_metadata
      self.parsed_metadata = self.raw_metadata
      add_local
      return self.parsed_metadata
    end

    def collections_created?
      true
    end
  end
end
