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
      "#{order_value(params&.[]('order')&.[]('0')&.[]('column'))} #{params&.[]('order')&.[]('0')&.[]('dir')}" if params&.[]('order')&.[]('0')&.[]('column').present?
    end

    # convert offset to page number
    def table_page
      params[:start].blank? ? 1 : (params[:start].to_i / params[:length].to_i) + 1
    end

    def entry_table_search
      return @entry_table_search if @entry_table_search
      return @entry_table_search = false if params['search']&.[]('value').blank?

      table_search_value = params['search']&.[]('value')&.downcase

      ['identifier', 'id', 'status_message', 'type', 'updated_at'].map do |col|
        column = Bulkrax::Entry.arel_table[col]
        column = Arel::Nodes::NamedFunction.new('CAST', [column.as('text')])
        column = Arel::Nodes::NamedFunction.new('LOWER', [column])
        @entry_table_search = if @entry_table_search
                          @entry_table_search.or(column.matches("%#{table_search_value}%"))
                        else
                          column.matches("%#{table_search_value}%")
                        end
      end

      @entry_table_search
    end

    def importer_table_search
      return @importer_table_search if @importer_table_search
      return @importer_table_search = false if params['search']&.[]('value').blank?

      table_search_value = params['search']&.[]('value')&.downcase

      ['name', 'id', 'status_message', 'last_error_at', 'last_succeeded_at', 'updated_at'].map do |col|
        column = Bulkrax::Importer.arel_table[col]
        column = Arel::Nodes::NamedFunction.new('CAST', [column.as('text')])
        column = Arel::Nodes::NamedFunction.new('LOWER', [column])
        @importer_table_search = if @importer_table_search
                          @importer_table_search.or(column.matches("%#{table_search_value}%"))
                        else
                          column.matches("%#{table_search_value}%")
                        end
      end

      @importer_table_search
    end

    def format_importers(importers)
      result = importers.map do |i|
        {
          name: view_context.link_to(i.name, view_context.importer_path(i)),
          status_message: status_message_for(i),
          last_imported_at: i.last_imported_at&.strftime("%b %d, %Y"),
          next_import_at: i.next_import_at&.strftime("%b %d, %Y"),
          enqueued_records: i.last_run&.enqueued_records,
          processed_records: i.last_run&.processed_records || 0,
          failed_records: i.last_run&.failed_records || 0,
          deleted_records: i.last_run&.deleted_records,
          total_collection_entries: i.last_run&.total_collection_entries,
          total_work_entries: i.last_run&.total_work_entries,
          total_file_set_entries: i.last_run&.total_file_set_entries,
          actions: importer_util_links(i)
        }
      end
      {
        data: result,
        recordsTotal: Bulkrax::Importer.count,
        recordsFiltered: importers.size
      }
    end

    def format_entries(entries, item)
      result = entries.map do |e|
        {
          identifier: view_context.link_to(e.identifier, view_context.item_entry_path(item, e)),
          id: e.id,
          status_message: status_message_for(e),
          type: e.type,
          updated_at: e.updated_at,
          errors: e.latest_status&.error_class&.present? ? view_context.link_to(e.latest_status.error_class, view_context.item_entry_path(item, e), title: e.latest_status.error_message) : "",
          actions: entry_util_links(e, item)
        }
      end
      {
        data: result,
        recordsTotal: item.entries.size,
        recordsFiltered: item.entries.size
      }
    end

    def entry_util_links(e, item)
      links = []
      links << view_context.link_to(view_context.raw('<span class="glyphicon glyphicon-info-sign"></span>'), view_context.item_entry_path(item, e))
      links << "<a class='glyphicon glyphicon-repeat' data-toggle='modal' data-target='#bulkraxItemModal' data-entry-id='#{e.id}'></a>" if view_context.an_importer?(item)
      links << view_context.link_to(view_context.raw('<span class="glyphicon glyphicon-trash"></span>'), view_context.item_entry_path(item, e), method: :delete, data: { confirm: 'This will delete the entry and any work associated with it. Are you sure?' })
      links.join(" ")
    end

    def status_message_for(e)
      if e.status_message == "Complete"
        "<td><span class='glyphicon glyphicon-ok' style='color: green;'></span> #{e.status_message}</td>"
      elsif e.status_message == "Pending"
        "<td><span class='glyphicon glyphicon-option-horizontal' style='color: blue;'></span> #{e.status_message}</td>"
      elsif e.status_message == "Skipped"
        "<td><span class='glyphicon glyphicon-step-forward' style='color: yellow;'></span> #{e.status_message}</td>"
      else
        "<td><span class='glyphicon glyphicon-remove' style='color: #{e.status == 'Deleted' ? 'green' : 'red'};'></span> #{e.status_message}</td>"
      end
    end

    def importer_util_links(i)
      links = []
      links << view_context.link_to(view_context.raw('<span class="glyphicon glyphicon-info-sign"></span>'), importer_path(i))
      links << view_context.link_to(view_context.raw('<span class="glyphicon glyphicon-pencil"></span>'), edit_importer_path(i))
      links << view_context.link_to(view_context.raw('<span class="glyphicon glyphicon-remove"></span>'), i, method: :delete, data: { confirm: 'Are you sure?' })
      links.join(" ")
    end
  end
end
