module Bulkrax
  class CdriParser < ApplicationParser
    attr_accessor :data, :running_count
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

    def create_collections_with_works
      data.css('Collections').each do |collection_xml|
        collection = CdriCollectionEntry.create(importer: self.importer, raw_metadata: collection_xml).build
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
          new_entry = entry_class.create(importer: self.importer, raw_metadata: component_xml, collection_id: collection.id)
          ImportWorkJob.perform_later(new_entry.id, importer.current_importer_run.id)
          ImporterRun.find(current_importer_run.id).increment!(:processed_records)
        rescue => e
          debugger
          Rails.logger.error "Import ERROR: #{component_xml["ComponentID"].to_s} - Message: #{e.message}"
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

    def total
      @total ||= data.css('Components').count
    rescue
      @total = 0
    end

  end
end
