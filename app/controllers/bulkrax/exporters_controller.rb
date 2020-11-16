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
      @exporters = Exporter.all

      add_exporter_breadcrumbs
    end

    # GET /exporters/1
    def show
      add_exporter_breadcrumbs
      add_breadcrumb @exporter.name

      @work_entries = @exporter.entries.where(type: @exporter.parser.entry_class.to_s).page(params[:work_entries_page])
    end

    # GET /exporters/new
    def new
      @exporter = Exporter.new

      add_exporter_breadcrumbs
      add_breadcrumb 'New'
    end

    # GET /exporters/1/edit
    def edit
      add_exporter_breadcrumbs
      add_breadcrumb @exporter.name, bulkrax.exporter_path(@exporter.id)
      add_breadcrumb 'Edit'

      # Correctly populate export_source_collection input
      @collection = Collection.find(@exporter.export_source) if @exporter.export_source.present? && @exporter.export_from == 'collection'
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

      # Only allow a trusted parameters through.
      def exporter_params
        params[:exporter][:export_source] = params[:exporter]["export_source_#{params[:exporter][:export_from]}".to_sym]
        if params[:exporter][:date_filter] == "1"
          params.fetch(:exporter).permit(:name, :user_id, :export_source, :export_from, :export_type,
                                         :parser_klass, :limit, :start_date, :finish_date, :work_visibility, field_mapping: {})
        else
          params.fetch(:exporter).permit(:name, :user_id, :export_source, :export_from, :export_type,
                                         :parser_klass, :limit, :work_visibility, field_mapping: {}).merge(start_date: nil, finish_date: nil)
        end
      end

      # Add the field_mapping from the Bulkrax configuration
      def field_mapping_params
        # @todo replace/append once mapping GUI is in place
        field_mapping_key = Bulkrax.parsers.map { |m| m[:class_name] if m[:class_name] == params[:exporter][:parser_klass] }.compact.first
        @exporter.field_mapping = Bulkrax.field_mappings[field_mapping_key] if field_mapping_key
      end

      def add_exporter_breadcrumbs
        add_breadcrumb t(:'hyrax.controls.home'), main_app.root_path
        add_breadcrumb t(:'hyrax.dashboard.breadcrumbs.admin'), hyrax.dashboard_path
        add_breadcrumb 'Exporters', bulkrax.exporters_path
      end

      # Download methods

      def file_path
        @exporter.exporter_export_zip_path
      end
  end
end
