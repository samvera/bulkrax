# frozen_string_literal: true

module Bulkrax
  class ExportersController < ApplicationController
    include Hyrax::ThemedLayoutController if defined?(::Hyrax)
    include Bulkrax::DownloadBehavior
    include Bulkrax::DatatablesBehavior
    before_action :authenticate_user!
    before_action :check_permissions
    before_action :set_exporter, only: [:show, :entry_table, :edit, :update, :destroy]
    with_themed_layout 'dashboard' if defined?(::Hyrax)

    # GET /exporters
    def index
      # NOTE: We're paginating this in the browser.
      @exporters = Exporter.order(created_at: :desc).all

      add_exporter_breadcrumbs if defined?(::Hyrax)
    end

    def exporter_table
      @exporters = Exporter.order(table_order).page(table_page).per(table_per_page)
      @exporters = @exporters.where(exporter_table_search) if exporter_table_search.present?
      respond_to do |format|
        format.json { render json: format_exporters(@exporters) }
      end
    end

    # GET /exporters/1
    def show
      if defined?(::Hyrax)
        add_exporter_breadcrumbs
        add_breadcrumb @exporter.name
      end
      @first_entry = @exporter.entries.first
    end

    def entry_table
      @entries = @exporter.entries.order(table_order).page(table_page).per(table_per_page)
      @entries = @entries.where(entry_table_search) if entry_table_search.present?
      respond_to do |format|
        format.json { render json: format_entries(@entries, @exporter) }
      end
    end

    # GET /exporters/new
    def new
      @exporter = Exporter.new
      return unless defined?(::Hyrax)
      add_exporter_breadcrumbs
      add_breadcrumb 'New'
    end

    # GET /exporters/1/edit
    def edit
      if defined?(::Hyrax)
        add_exporter_breadcrumbs
        add_breadcrumb @exporter.name, bulkrax.exporter_path(@exporter.id)
        add_breadcrumb 'Edit'
      end

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
          Bulkrax::ExporterJob.perform_later(@exporter.id)
          message = 'Exporter was successfully created. A download link will appear once it completes.'
        else
          message = 'Exporter was successfully created.'
        end
        redirect_to exporters_path, notice: message
      else
        render :new
      end
    end

    # PATCH/PUT /exporters/1
    def update
      field_mapping_params
      if @exporter.update(exporter_params)
        if params[:commit] == 'Update and Re-Export All Items'
          Bulkrax::ExporterJob.perform_later(@exporter.id)
          message = 'Exporter was successfully updated. A download link will appear once it completes.'
        else
          'Exporter was successfully updated.'
        end
        redirect_to exporters_path, notice: message
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
      @exporter = Exporter.find(params[:id] || params[:exporter_id])
    end

    # Only allow a trusted parameters through.
    def exporter_params
      params[:exporter][:export_source] = params[:exporter]["export_source_#{params[:exporter][:export_from]}".to_sym]
      if params[:exporter][:date_filter] == "1"
        params.fetch(:exporter).permit(:name, :user_id, :export_source, :export_from, :export_type, :generated_metadata,
                                       :include_thumbnails, :parser_klass, :limit, :start_date, :finish_date, :work_visibility,
                                       :workflow_status, field_mapping: {})
      else
        params.fetch(:exporter).permit(:name, :user_id, :export_source, :export_from, :export_type, :generated_metadata,
                                       :include_thumbnails, :parser_klass, :limit, :work_visibility, :workflow_status,
                                       field_mapping: {}).merge(start_date: nil, finish_date: nil)
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
      "#{@exporter.exporter_export_zip_path}/#{params['exporter']['exporter_export_zip_files']}"
    end

    def check_permissions
      raise CanCan::AccessDenied unless current_ability.can_export_works?
    end
  end
end
