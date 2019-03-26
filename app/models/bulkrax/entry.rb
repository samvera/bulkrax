module Bulkrax
  class Entry < ApplicationRecord
    belongs_to :importer

    attr_accessor :all_attrs

    delegate :parser,
             to: :importer

    delegate :client,
             :mapping_class,
             :collection_name,
             :user,
             to: :parser

    def build
      # attributes, files_dir = nil, files = [], user = nil
      Bulkrax::ApplicationFactory.for(entry_class.to_s).new(all_attrs, nil, [], user).run
    end

    def mapping
      @mapping ||= mapping_class.new(
        raw_record,
        parser.parser_fields['rights_statement'],
        parser.parser_fields['override_rights_statement'],
        parser.parser_fields['institution_name'],
        parser.parser_fields['thumbnail_url'],
        collection_name == "all"
      )
    end

    def all_attrs
      return @all_attrs if @all_attrs
      @all_attrs ||= mapping.all_attrs
      unless collection_name == "all"
        @all_attrs['collections'] ||= []
        @all_attrs['collections'] << {id: parser.collection&.id}
      end
      return @all_attrs
    end
  end
end
