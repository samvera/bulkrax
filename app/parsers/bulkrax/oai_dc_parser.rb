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
        override_rights_statement: :boolean,
        thumbnail_url: :string
      }
    end

    def initialize(importer)
      super
      @headers = { from: importer.user.email }
    end

    def client
      @client ||= OAI::Client.new(importer.parser_fields['base_url'],
                                  headers: headers,
                                  parser: 'libxml',
                                  metadata_prefix: importer.parser_fields['metadata_prefix'])
    end

    def collection_name
      @collection_name ||= parser_fields['set'] || 'all'
    end

    def collection
      @collection ||= Collection.where(identifier: [collection_name]).first
    end

    def entry_class
      OaiDcEntry
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
          @records ||= client.list_records(opts.merge(metadata_prefix: parser_fields['metadata_prefix']))
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
            contributing_institution: [parser_fields['institution_name']],
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
      results = self.records(quick: true)
      if results.present?
        results.full.each_with_index do |record, index|
          if !limit.nil? && index >= limit
            break
          elsif record.deleted? # TODO record.status == "deleted"
            importer.current_importer_run.deleted_records += 1
            importer.current_importer_run.save!
          else
            seen[record.identifier] = true
            new_entry = entry_class.where(importer: self.importer, identifier: record.identifier).first_or_create! do |e|
              e.collection_id = self.collection.id
            end
            ImportWorkJob.perform_later(new_entry.id, importer.current_importer_run.id)
            importer.increment_counters(index)
          end
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
