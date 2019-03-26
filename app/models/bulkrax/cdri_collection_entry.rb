module Bulkrax
  class CdriCollectionEntry < Entry
    def initialize(attrs={})
      super(attrs)
      self.identifier = raw_metadata_xml['CollectionNameCode'].to_s
    end

    def entry_class
      Collection
    end

    def raw_metadata_xml
      @raw_metadata_xml ||= Nokogiri::XML.fragment(raw_metadata).elements.first
    end

    def all_attrs
      return @all_attrs if @all_attrs.present?
      @all_attrs = raw_metadata_xml.each_with_object({}) do |(key, value), hash|
        clean_key = key.gsub(/collection/i, '').gsub(/\d+/, '').underscore
        if entry_class.new.respond_to?(clean_key.to_sym) && clean_key != 'id'
          hash[clean_key] ||= []
          val = val.respond_to?(:value) ? value.value : value
          hash[clean_key] << val.gsub(/\n|\r|\r\n/, ' ').strip
        end
      end

      @all_attrs['visibility'] = 'open'
      @all_attrs['collection_type_gid'] = Hyrax::CollectionType.find_or_create_default_collection_type.gid
      @all_attrs['identifier'] = [self.identifier]
      @all_attrs
    end
  end
end
