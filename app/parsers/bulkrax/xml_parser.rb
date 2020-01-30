# frozen_string_literal: true
module Bulkrax
  class XmlParser < ApplicationParser
    def entry_class; end

    def collection_entry_class; end

    def records(opts = {}); end

    def create_collections; end

    def create_works; end

    # def valid_import?; end (default: true)
    # def total; end (default: 0)
  end
end
