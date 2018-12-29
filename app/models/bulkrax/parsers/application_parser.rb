module Bulkrax
  module Parsers
    class ApplicationParser

      #attr_accessor :url, :headers, :file_url, :user, :admin_set_id, :rights, :institution, :total, :client, :collection_name, :metadata_prefix
      attr_accessor :importer, :total

      def self.parser_fields
        {}
      end

      def initialize(importer)
        @importer = importer
      end

      # @api
      def entry_class
        raise 'must be defined'
      end

      # @api
      def mapping_class
        raise 'must be defined'
      end

      # @api
      def records(opts = {})
        raise 'must be defined'
      end

      def record(identifier, opts = {})
        return @record if @record

        @record = entry_class.new(self, identifier)
        @record.build
        return @record
      end

      def total
        0
      end

    end
  end
end
