module Bulkrax
  class CdriWorkEntry < Entry
    include Bulkrax::Concerns::HasMatchers
    matcher 'contributing_institution', from: ['publisher']
    matcher 'creator', split: true
    matcher 'date', from: ['date', 'pub_date'], split: true
    matcher 'description'
    matcher 'language', parsed: true, split: /\s*,\s*/
    matcher 'place', from: ['pub_place']
    matcher 'subject', parsed: true
    matcher 'title'

    def initialize(attrs={})
      super(attrs)
      self.identifier = raw_metadata_xml['ComponentID'].to_s
    end

    # override to provide file directory
    def build
      # attributes, files_dir = nil, files = [], user = nil
      Bulkrax::ApplicationFactory.for(entry_class.to_s).new(build_metadata, File.join(parser.parser_fields['upload_path'], collection.name_code.first) , [], user).run
    end

    def entry_class
      Work
    end

    def raw_metadata_xml
      @raw_metadata_xml ||= Nokogiri::XML.fragment(raw_metadata).elements.first
    end

    def build_metadata
      self.parsed_metadata = {}
      raw_metadata_xml.each_with_object({}) do |(key, value), hash|
        clean_key = key.gsub(/component/i, '').gsub(/\d+/, '').underscore.downcase
        next if clean_key == 'id'
        val = value.respond_to?(:value) ? value.value : value
        add_metadata(clean_key, val)
      end

      # remove any unspported attributes
      object = entry_class.new
      self.parsed_metadata = self.parsed_metadata.select do |key, value|
        object.respond_to?(key.to_sym)
      end

      self.parsed_metadata['visibility'] = 'open'
      self.parsed_metadata['rights_statement'] = [parser.parser_fields['rights_statement']]
      self.parsed_metadata['collections'] ||= []
      self.parsed_metadata['collections'] << {id: self.collection&.id}
      self.parsed_metadata['file'] = [raw_metadata_xml["ComponentFileName"]] if raw_metadata_xml["ComponentFileName"].present?
      self.parsed_metadata['identifier'] ||= [self.identifier]
      return self.parsed_metadata
    end
  end
end
