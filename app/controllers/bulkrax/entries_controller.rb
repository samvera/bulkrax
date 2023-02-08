# frozen_string_literal: true

require_dependency "bulkrax/application_controller"
require_dependency "oai"

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
