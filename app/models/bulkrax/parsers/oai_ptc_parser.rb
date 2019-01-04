module Bulkrax
  module Parsers
    class OaiPtcParser < OaiDcParser
      def mapping_class
        Mappings::OaiPtcMapping
      end

   end
  end
end
