module Bulkrax
  class Entry < ApplicationRecord
    include Bulkrax::Concerns::HasMatchers

    belongs_to :importer
    serialize :parsed_metadata, JSON

    attr_accessor :all_attrs

    delegate :parser,
             to: :importer

    delegate :client,
             :collection_name,
             :user,
             to: :parser

    def build
      # attributes, files_dir = nil, files = [], user = nil
      Bulkrax::ApplicationFactory.for(entry_class.to_s).new(build_metadata, nil, [], user).run
    end

    def collection
      @collection ||= Collection.find(self.collection_id) if self.collection_id
    end

    def build_metadata
      raise 'Not Implemented'
    end
  end
end
