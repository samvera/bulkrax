module Bulkrax
  class CdriParser < ApplicationParser
    attr_accessor :data, :running_count
    def self.parser_fields
      {
        xml_path: :string,
        upload_path: :string,
        institution_name: :string,
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
        collection = CdriCollectionEntry.new(self, collection_xml).build
        create_works(collection_xml, collection)
        if limit && running_count >= limit
          break
        end
      end
    end

    def create_works(collection_xml, collection)
      collection_xml.css('Components').map do |component_xml|
        ImporterRun.find(current_importer_run.id).increment!(:enqueued_records)

        work = CdriWorkEntry.new(self, component_xml, collection).build
        ImporterRun.find(current_importer_run.id).increment!(:processed_records) if work.valid?

        self.running_count += 1
        if limit && running_count >= limit
          break
        end
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
