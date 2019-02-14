module Bulkrax
  class CdriWorkEntry < ApplicationEntry
    def initialize(parser, attrs, collection)
      @parser = parser
      @attrs = attrs
      @identifier = attrs["ComponentID"].to_s
      @collection_id = collection.id
      @collection = collection
    end

    # override to provide file directory
    def build
      # attributes, files_dir = nil, files = [], user = nil
      Bulkrax::ApplicationFactory.for(entry_class.to_s).new(all_attrs, File.join(parser.parser_fields['upload_path'], @collection.name_code.first) , [], user).run
    end

    def entry_class
      Work
    end

    def all_attrs
      return @all_attrs if @all_attrs.present?

      @all_attrs = @attrs.each_with_object({}) do |(key, value), hash|
        clean_key = key.gsub(/component/i, '').gsub(/\d+/, '').underscore
        if(clean_key.match(/publisher/i))
          hash['contributing_institution'] ||= []
          val = val.respond_to?(:value) ? value.value : value
          hash['contributing_institution'] << val.gsub(/\n|\r|\r\n/, ' ').strip
        else
          if entry_class.new.respond_to?(clean_key.to_sym) && clean_key != 'id'
            hash[clean_key] ||= []
            val = val.respond_to?(:value) ? value.value : value
            hash[clean_key] << val.gsub(/\n|\r|\r\n/, ' ').strip
          end
        end
      end
      @all_attrs['visibility'] = 'open'
      @metadata['rights_statement'] = [parser.parser_fields['rights_statement']]
      @all_attrs['collection'] = {id: @collection_id}
      @all_attrs['file'] = [@attrs["ComponentFileName"]] if @attrs["ComponentFileName"].present?
      @all_attrs
    end
  end
end
