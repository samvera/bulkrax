# frozen_string_literal: true
module Bulkrax
  class FoxmlEntry < Entry
    def self.fields_from_data(data); end

    def self.read_data(path); end

    def self.data_for_entry(data, path = nil); end

    # def self.collection_field; end
    # def self.children_field; end
    # def self.matcher_class; end

    def record; end

    def build_metadata; end

    # def collections_created?; end
    # def find_or_create_collection_ids; end
  end
end
