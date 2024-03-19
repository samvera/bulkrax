# frozen_string_literal: true

module Bulkrax
  class OaiSetEntry < OaiEntry
    # TODO: Similar to the has_model_ssim conundrum; we want to ask for the
    # collection_model_class_type.â
    self.default_work_type = "Collection"

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
