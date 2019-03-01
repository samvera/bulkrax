module Bulkrax
  class CdriParser < ApplicationParser
    attr_accessor :data, :running_count, :cdri_collection
    def self.parser_fields
      {
        xml_path: :string,
        upload_path: :string,
        rights_statements: :string,
      }
    end

    def initialize(importer)
      @running_count = 0
      super
    end

    def data
      @data ||= File.open(importer.parser_fields['xml_path']) { |f| Nokogiri::XML(f).remove_namespaces! }
    end

    def run
      create_collections_with_works
    end

    def running_count
      @running_count ||= 0
    end

    def cdri_collection
      return @cdri_collection if @cdri_collection
      @cdri_collection = Collection.where(identifier: ['cdri']).first
      @cdri_collection ||= CollectionFactory.new({identifier: ['cdri'],
                                                  title: ["CDRI"],
                                                  visibility: 'open',
                                                  collection_type_gid: Hyrax::CollectionType.find_or_create_default_collection_type.gid
                                                 }).find_or_create
      @cdri_collection.reindex_extent = Hyrax::Adapters::NestingIndexAdapter::LIMITED_REINDEX
      return @cdri_collection
    end

    def create_collections_with_works
      self.cdri_collection # make sure it is created before we start

      data.css('Collections').each do |collection_xml|
        collection = CdriCollectionEntry.new(self, collection_xml).build
        create_works(collection_xml, collection)
        if limit && running_count >= limit
          break
        end
      end
    end

    def create_works(collection_xml, collection)
      collection_xml.css('Components').select do |component_xml|
        ImporterRun.find(current_importer_run.id).increment!(:enqueued_records)
        if Work.where(identifier: [component_xml["ComponentID"].to_s]).count > 0
          ImporterRun.find(current_importer_run.id).increment!(:processed_records)
          puts "skipped #{component_xml["ComponentID"]}"
          next
        end
        begin
          work = CdriWorkEntry.new(self, component_xml, collection).build
          if work.valid?
            ImporterRun.find(current_importer_run.id).increment!(:processed_records)
          else
            Rails.logger.error "Import ERROR: #{component_xml["ComponentID"].to_s} - #{work.errors.full_messages}"
            ImporterRun.find(current_importer_run.id).increment!(:failed_records)
          end
        rescue => e
          Rails.logger.error "Import ERROR: #{component_xml["ComponentID"].to_s}"
          ImporterRun.find(current_importer_run.id).increment!(:failed_records)
        end
        self.running_count += 1
        if limit && running_count >= limit
          break
        end
        false
      end
    end

    def entry_class
      CdriWorkEntry
    end

    def mapping_class
      CdriMapping
    end

    def entry(identifier)
      entry_class.new(self, identifier)
    end


    def total
      @total ||= data.css('Components').count
    rescue
      @total = 0
    end

  end
end
