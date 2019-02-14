module Bulkrax
  class OaiDcParser < ApplicationParser
    attr_accessor :client, :headers
    delegate :list_sets, to: :client

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
      OaiEntry
    end

    def mapping_class
      OaiDcMapping
    end

    def entry(identifier)
      entry_class.new(self, identifier)
    end

    def records(opts = {})
      if parser_fields['set'].present?
        opts.merge!(set: parser_fields['set'])
      end

      if importer.last_imported_at && only_updates
        opts.merge!(from: importer&.last_imported_at&.strftime("%Y-%m-%d"))
      end

      if opts[:quick]
        opts.delete(:quick)
        begin
          @short_records = client.list_identifiers(opts)
        rescue OAI::Exception => e
          if e.code == "noRecordsMatch"
            @short_records = []
          else
            raise e
          end
        end
      else
        begin
          @records ||= client.list_records(opts)
        rescue OAI::Exception => e
          if e.code == "noRecordsMatch"
            @records = []
          else
            raise e
          end
        end
      end
    end

    def list_sets
      client.list_sets
    end

    def run
      create_collections
      create_works
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
          #Bulkrax::CollectionFactory.new(attrs).find_or_create
          collection = Collection.where(identifier: [set.spec]).first
          collection ||= Collection.create!(attrs)
        end
      end
    end

    def create_works
      self.records(quick: true).full.each_with_index do |record, index|
        if !limit.nil? && index >= limit
          break
        elsif record.deleted? # TODO record.status == "deleted"
          self.current_importer_run.deleted_records += 1
          self.current_importer_run.save!
        else
          seen[record.identifier] = true
          ImportWorkJob.perform_later(self.id, self.current_importer_run.id, record.identifier)
          self.increment_counters(index)
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
