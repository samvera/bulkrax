# frozen_string_literal: true

module Bulkrax
  module DatatablesBehavior
    extend ActiveSupport::Concern

    def table_per_page
      per_page = params[:length].to_i
      per_page < 1 ? 30 : per_page
    end

    def order_value(column)
      params['columns']&.[](column)&.[]('data')
    end

    def table_order
      "#{order_value(params['order']['0']['column'])} #{params['order']['0']['dir']}" if params['order']['0']['column'].present?
    end

    # convert offset to page number
    def table_page
      params[:start].blank? ? 1 : (params[:start].to_i / params[:length].to_i) + 1
    end

    def table_search
      return @table_search if @table_search
      return @table_search = false if params['search']&.[]('value').blank?

      table_search_value = params['search']&.[]('value')&.downcase

      ['identifier', 'id', 'status_message', 'type', 'updated_at'].map do |col|
        column = Bulkrax::Entry.arel_table[col].lower
        column = Arel::Nodes::NamedFunction.new('CAST', [column.as('text')])
        if @table_search
          @table_search = @table_search.or(column.matches("%#{table_search_value}%"))
        else
          @table_search = column.matches("%#{table_search_value}%")
        end
      end

      @table_search
    end

    def format_entries(entries, item)
      result = entries.map do |e|
        {
          identifier: view_context.link_to(e.identifier, view_context.item_entry_path(item, e)),
          id: e.id,
          status_message: entry_status(e),
          type: e.type,
          updated_at: e.updated_at,
          errors: e.latest_status&.error_class&.present? ? view_context.link_to(e.latest_status.error_class, view_context.item_entry_path(item, e), title: e.latest_status.error_message) : "",
          actions: util_links(e, item)
        }
      end
      {
        data: result,
        recordsTotal: item.entries.size,
        recordsFiltered: item.entries.size
      }
    end

    def util_links(e, item)
      links = []
      links << view_context.link_to(view_context.raw('<span class="glyphicon glyphicon-info-sign"></span>'), view_context.item_entry_path(item, e))
      links << "<a class='glyphicon glyphicon-repeat' data-toggle='modal' data-target='#bulkraxItemModal' data-entry-id='#{e.id}'></a>" if view_context.an_importer?(item)
      links << view_context.link_to(view_context.raw('<span class="glyphicon glyphicon-trash"></span>'), view_context.item_entry_path(item, e), method: :delete, data: { confirm: 'This will delete the entry and any work associated with it. Are you sure?' })
      links.join(" ")
    end

    def entry_status(e)
      if e.status_message == "Complete"
        "<td><span class='glyphicon glyphicon-ok' style='color: green;'></span> #{e.status_message}</td>"
      elsif e.status_message == "Pending"
        "<td><span class='glyphicon glyphicon-option-horizontal' style='color: blue;'></span> #{e.status_message}</td>"
      else
        "<td><span class='glyphicon glyphicon-remove' style='color: #{e.status == 'Deleted' ? 'green' : 'red'};'></span> #{e.status_message}</td>"
      end
    end
  end
end
