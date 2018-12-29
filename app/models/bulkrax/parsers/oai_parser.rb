module Bulkrax
  module Parsers
    class OaiParser < ApplicationParser
      attr_accessor :client, :headers
      delegate :list_sets, to: :client
      delegate :parser_fields, :user, to: :importer

      def self.parser_fields
        {
          base_url: :string,
          metadata_prefix: :string,
          set: :string,
          institution_name: :string,
          rights_statements: :string,
          thumbnail_url: :string
        }
      end

      def initialize(importer)
        super
        @headers = { from: importer.user.email }
      end

      def client
        @client ||= OAI::Client.new(parser_fields['base_url'],
                                    headers: headers,
                                    parser: 'libxml',
                                    metadata_prefix: importer.parser_fields['metadata_prefix'])
      end

      def collection_name
        @collection_name ||= parser_fields['set'] || 'all'
      end

      def entry_class
       Entries::OaiEntry
      end

      def mapping_class
        Mappings::OaiMapping
      end

      def entry(identifier)
        entry_class.new(self, identifier)
      end

      def records(opts = {})
        if opts[:quick]
          opts.delete(:quick)
          @short_records = client.list_identifiers(opts)
        else
          @records ||= client.list_records(opts)
        end
      end

      def list_sets
        client.list_sets
      end

      def create_collections
        list_sets.each do |set|
          if collection_name == 'all' || collection_name == set.spec
            attrs = {
              title: [set.name],
              identifier: [set.spec],
              institution: [parser_fields['institution_name']],
              visibility: 'open',
              collection_type_gid: Hyrax::CollectionType.find_or_create_default_collection_type.gid
            }
            #Bulkrax::Factories::CollectionFactory.new(attrs).find_or_create
            collection = Collection.where(identifier: [set.spec]).first
            collection ||= Collection.create!(attrs)
          end
        end
      end

      def total
        @total ||= records(quick: true).doc.find(".//resumptionToken").to_a.first.attributes["completeListSize"].to_i
      rescue
        @total = 0
      end

    end
  end
end
