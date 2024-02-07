# frozen_string_literal: true
module Bulkrax
  module ApplicationHelper
    def item_entry_path(item, e, opts = {})
      an_importer?(item) ? bulkrax.importer_entry_path(item.id, e.id, opts) : bulkrax.exporter_entry_path(item.id, e.id, opts)
    end

    def an_importer?(item)
      item.class.to_s.include?('Importer')
    end

    def coderay(value, opts)
      CodeRay
        .scan(value, :ruby)
        .html(opts)
        .html_safe # rubocop:disable Rails/OutputSafety
    end
  end
end
