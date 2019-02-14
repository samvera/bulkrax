module Bulkrax
  class CdriCollectionEntry < ApplicationEntry
    def initialize(parser, attrs)
      @parser = parser
      @attrs = attrs
      @identifier = attrs["CollectionNameCode"].to_s
    end

    def entry_class
      Collection
    end

    def all_attrs
      return @all_attrs if @all_attrs.present?

      @all_attrs = @attrs.each_with_object({}) do |(key, value), hash|
        clean_key = key.gsub(/collection/i, '').gsub(/\d+/, '').underscore
        if entry_class.new.respond_to?(clean_key.to_sym) && clean_key != 'id'
          hash[clean_key] ||= []
          val = val.respond_to?(:value) ? value.value : value
          hash[clean_key] << val.gsub(/\n|\r|\r\n/, ' ').strip
        end
      end

      @all_attrs['visibility'] = 'open'
      @all_attrs['collection_type_gid'] = Hyrax::CollectionType.find_or_create_default_collection_type.gid
      @all_attrs['institution'] = [parser.parser_fields['institution_name']] if parser.parser_fields['institution_name'].present?
      @all_attrs['identifier'] = [@identifier]
      @all_attrs
    end

  end
end
