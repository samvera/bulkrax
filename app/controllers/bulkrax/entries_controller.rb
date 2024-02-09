# frozen_string_literal: true

module Bulkrax
  class EntriesController < ApplicationController
    include Hyrax::ThemedLayoutController if defined?(::Hyrax)
    before_action :authenticate_user!
    before_action :check_permissions
    with_themed_layout 'dashboard' if defined?(::Hyrax)

    def show
      if params[:importer_id].present?
        show_importer
      elsif params[:exporter_id].present?
        show_exporter
      end
    end

    def update
      @entry = Entry.find(params[:id])
      type = case @entry.type.downcase
             when /fileset/
               'file_set'
             when /collection/
               'collection'
             else
               'work'
             end
      item = @entry.importerexporter
      # do not run counters as it loads the whole parser
      current_run = item.current_run(skip_counts: true)
      @entry.set_status_info('Pending', current_run)
      if params[:destroy_first]
      "Bulkrax::DeleteAndImport#{type.camelize}Job".constantize.perform_later(@entry, current_run)
      else
        "Bulkrax::Import#{type.camelize}Job".constantize.perform_later(@entry.id, current_run.id)
      end

      entry_path = item.class.to_s.include?('Importer') ? bulkrax.importer_entry_path(item.id, @entry.id) : bulkrax.exporter_entry_path(item.id, @entry.id)

      redirect_back fallback_location: entry_path, notice: "Entry #{@entry.id} update has been queued"
    end

    def destroy
      @entry = Entry.find(params[:id])
      @status = ""
      begin
        work = @entry.factory&.find
        if work.present?
          work.destroy
          @entry.destroy
          @status = "Entry and work deleted"
        else
          @entry.destroy
          @status = "Entry deleted"
        end
      rescue StandardError => e
        @status = "Error: #{e.message}"
      end

      item = @entry.importerexporter
      entry_path = item.class.to_s.include?('Importer') ? bulkrax.importer_entry_path(item.id, @entry.id) : bulkrax.exporter_entry_path(item.id, @entry.id)

      redirect_back fallback_location: entry_path, notice: @status
    end

    protected

    # GET /importers/1/entries/1
    def show_importer
      @importer = Importer.find(params[:importer_id])
      @entry = Entry.find(params[:id])

      return unless defined?(::Hyrax)
      add_breadcrumb t(:'hyrax.controls.home'), main_app.root_path
      add_breadcrumb t(:'hyrax.dashboard.breadcrumbs.admin'), hyrax.dashboard_path
      add_breadcrumb 'Importers', bulkrax.importers_path
      add_breadcrumb @importer.name, bulkrax.importer_path(@importer.id)
      add_breadcrumb @entry.id
    end

    # GET /exporters/1/entries/1
    def show_exporter
      @exporter = Exporter.find(params[:exporter_id])
      @entry = Entry.find(params[:id])

      return unless defined?(::Hyrax)
      add_breadcrumb t(:'hyrax.controls.home'), main_app.root_path
      add_breadcrumb t(:'hyrax.dashboard.breadcrumbs.admin'), hyrax.dashboard_path
      add_breadcrumb 'Exporters', bulkrax.exporters_path
      add_breadcrumb @exporter.name, bulkrax.exporter_path(@exporter.id)
      add_breadcrumb @entry.id
    end

    def check_permissions
      raise CanCan::AccessDenied unless current_ability.can_import_works? || current_ability.can_export_works?
    end
  end
end
