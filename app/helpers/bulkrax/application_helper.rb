# frozen_string_literal: true
module Bulkrax
  module ApplicationHelper
    def item_entry_path(item, e, opts = {})
      an_importer?(item) ? bulkrax.importer_entry_path(item.id, e.id, opts) : bulkrax.exporter_entry_path(item.id, e.id, opts)
    end

    def an_importer?(item)
      item.class.to_s.include?('Importer')
    end

    # Returns a Bootstrap badge for the given status_message string.
    # Used by the importers datatable and the metrics dashboard.
    def status_badge(status_message)
      case status_message
      when 'Complete'
        icon = 'fa-check'
        color = 'green'
      when 'Pending'
        icon = 'fa-ellipsis-h'
        color = 'blue'
      when 'Skipped'
        icon = 'fa-step-forward'
        color = 'yellow'
      when 'Deleted'
        icon = 'fa-remove'
        color = 'green'
      else
        icon = 'fa-remove'
        color = 'red'
      end

      "<span class='fa #{icon}' style='color: #{color};'></span> #{ERB::Util.html_escape(status_message || '--')}".html_safe # rubocop:disable Rails/OutputSafety
    end

    def coderay(value, opts)
      CodeRay
        .scan(value, :ruby)
        .html(opts)
        .html_safe # rubocop:disable Rails/OutputSafety
    end
  end
end
