module Bulkrax
  module Parsers
    class OaiQualifiedDcParser < OaiDcParser
      def mapping_class
        Mappings::OaiQualifiedDcMapping
      end

   end
  end
end
