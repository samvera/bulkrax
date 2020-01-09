# frozen_string_literal: true

require_dependency "bulkrax/application_controller"

module Bulkrax
  class ExportersController < ApplicationController
    include Hyrax::ThemedLayoutController
    include Bulkrax::DownloadBehavior
    before_action :authenticate_user!
    before_action :set_exporter, only: [:show, :edit, :update, :destroy]
    with_themed_layout 'dashboard'

    # GET /exporters
    def index
      add_breadcrumb t(:'hyrax.controls.home'), main_app.root_path
      add_breadcrumb t(:'hyrax.dashboard.breadcrumbs.admin'), hyrax.dashboard_path
      add_breadcrumb 'Exporters', bulkrax.exporters_path
      @exporters = Exporter.all
    end

    # GET /exporters/1
    def show; end

    # GET /exporters/new
    def new
      add_breadcrumb t(:'hyrax.controls.home'), main_app.root_path
      add_breadcrumb t(:'hyrax.dashboard.breadcrumbs.admin'), hyrax.dashboard_path
      add_breadcrumb 'Exporters', bulkrax.exporters_path
      @exporter = Exporter.new
    end

    # GET /exporters/1/edit
    def edit
      add_breadcrumb t(:'hyrax.controls.home'), main_app.root_path
      add_breadcrumb t(:'hyrax.dashboard.breadcrumbs.admin'), hyrax.dashboard_path
      add_breadcrumb 'Exporters', bulkrax.exporters_path
    end

    # POST /exporters
    def create
      @exporter = Exporter.new(exporter_params)
      field_mapping_params

      if @exporter.save
        if params[:commit] == 'Create and Export'
          # Use perform now for export
          Bulkrax::ExporterJob.perform_now(@exporter.id)
        end
        redirect_to exporters_path, notice: 'Exporter was successfully created.'
      else
        render :new
      end
    end

    # PATCH/PUT /exporters/1
    def update
      field_mapping_params
      if @exporter.update(exporter_params)
        Bulkrax::ExporterJob.perform_now(@exporter.id) if params[:commit] == 'Update and Re-Export All Items'
        redirect_to exporters_path, notice: 'Exporter was successfully updated.'
      else
        render :edit
      end
    end

    # DELETE /exporters/1
    def destroy
      @exporter.destroy
      redirect_to exporters_url, notice: 'Exporter was successfully destroyed.'
    end

    # GET /exporters/1/download
    def download
      @exporter = Exporter.find(params[:exporter_id])
      send_content
    end

    private

      # Use callbacks to share common setup or constraints between actions.
      def set_exporter
        @exporter = Exporter.find(params[:id])
      end

      # Only allow a trusted parameter "white list" through.
      def exporter_params
        params.fetch(:exporter).permit(:name, :user_id, :export_source, :export_from, :export_type, :parser_klass, :limit, field_mapping: {})
      end

      def field_mapping_params
        # @todo replace/append once mapping GUI is in place
        fields = Bulkrax.parsers.map { |m| m[:partial] if m[:class_name] == params[:exporter][:parser_klass] }.compact.first
        @exporter.field_mapping = Bulkrax.field_mappings[fields.to_sym] if fields
      end

      # Download methods

      def file_path
        @exporter.exporter_export_zip_path
      end

      def file
        @file ||= File.open(file_path, 'r')
      end

      # Override this if you'd like a different filename
      # @return [String] the filename
      def file_name
        file_path.split('/').last
      end
  end
end
