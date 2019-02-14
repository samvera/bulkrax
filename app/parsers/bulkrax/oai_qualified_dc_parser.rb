module Bulkrax
  class OaiQualifiedDcParser < OaiDcParser
    def mapping_class
      Mappings::OaiQualifiedDcMapping
    end
  end
end
