# frozen_string_literal: true

module Bulkrax
  class OaiDcParser < ApplicationParser
    attr_accessor :headers
    delegate :list_sets, to: :client

    def initialize(importerexporter)
      super
      @headers = { from: importerexporter.user.email }
    end

    def client
      @client ||= OAI::Client.new(importerexporter.parser_fields['base_url'],
                                  headers: headers,
                                  parser: 'libxml')
    rescue StandardError
      raise OAIError
    end

    def collection_name
      @collection_name ||= parser_fields['set'] || 'all'
    end

    def entry_class
      OaiDcEntry
    end

    def collection_entry_class
      OaiSetEntry
    end

    def file_set_entry_class; end

    def records(opts = {})
      opts[:metadata_prefix] ||= importerexporter.parser_fields['metadata_prefix']
      opts[:set] = collection_name unless collection_name == 'all'

      opts[:from] = importerexporter&.last_imported_at&.strftime("%Y-%m-%d") if importerexporter.last_imported_at && only_updates

      if opts[:quick]
        opts.delete(:quick)
        begin
          @short_records = client.list_identifiers(opts)
        rescue OAI::Exception => e
          return @short_records = [] if e.code == "noRecordsMatch"
          raise e
        end
      else
        begin
          @records ||= client.list_records(opts.merge(metadata_prefix: parser_fields['metadata_prefix']))
        rescue OAI::Exception => e
          return @records = [] if e.code == "noRecordsMatch"
          raise e
        end
      end
    end

    # the set of fields available in the import data
    def import_fields
      ['contributor', 'coverage', 'creator', 'date', 'description', 'format', 'identifier', 'language', 'publisher', 'relation', 'rights', 'source', 'subject', 'title', 'type']
    end

    delegate :list_sets, to: :client

    def create_objects(types = [])
      types.each do |object_type|
        send("create_#{object_type.pluralize}")
      end
    end

    def create_collections
      metadata = {
        visibility: 'open'
      }
      metadata[:collection_type_gid] = Hyrax::CollectionType.find_or_create_default_collection_type.to_global_id.to_s if defined?(::Hyrax)

      collections.each_with_index do |set, index|
        next unless collection_name == 'all' || collection_name == set.spec
        unique_collection_identifier = importerexporter.unique_collection_identifier(set.spec)
        metadata[:title] = [set.name]
        metadata[work_identifier] = [unique_collection_identifier]

        new_entry = collection_entry_class.where(importerexporter: importerexporter, identifier: unique_collection_identifier, raw_metadata: metadata).first_or_create!
        # perform now to ensure this gets created before work imports start
        ImportCollectionJob.perform_now(new_entry.id, importerexporter.current_run.id)
        increment_counters(index, collection: true)
      end
    end

    def create_works
      results = self.records(quick: true)
      return if results.blank?
      results.full.each_with_index do |record, index|
        identifier = record_has_source_identifier(record, index)
        next unless identifier
        break if limit_reached?(limit, index)

        seen[identifier] = true
        create_entry_and_job(record, 'work', identifier)
        increment_counters(index, work: true)
      end
      importer.record_status
    rescue StandardError => e
      set_status_info(e)
    end

    # oai records so not let us set the source identifier easily
    def record_has_source_identifier(record, index)
      identifier = record.send(source_identifier)
      if identifier.blank?
        if Bulkrax.fill_in_blank_source_identifiers.present?
          identifier = Bulkrax.fill_in_blank_source_identifiers.call(self, index)
        else
          invalid_record("Missing #{source_identifier} for #{record.to_h}\n")
          return false
        end
      end
      identifier
    end

    def collections
      @collections ||= list_sets
    end

    def collections_total
      if collection_name == 'all'
        collections.count
      else
        1
      end
    end

    # TODO: change to differentiate between collection and work records when adding ability to import collection metadata
    def works_total
      total
    end

    def total
      @total ||= records(quick: true).doc.find(".//resumptionToken").to_a.first.attributes["completeListSize"].to_i
    rescue
      @total = 0
    end
  end
end
