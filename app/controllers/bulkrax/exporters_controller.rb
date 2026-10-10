# frozen_string_literal: true

module Bulkrax
  class ExportersController < ApplicationController
    include Hyrax::ThemedLayoutController if defined?(::Hyrax)
    include Bulkrax::DownloadBehavior
    include Bulkrax::DatatablesBehavior

    # Authentication, record loading and authorization for every action.
    before_action(except: [:download]) { authenticate_and_authorize!(Bulkrax::Exporter) }

    with_themed_layout 'dashboard' if defined?(::Hyrax)

    # GET /exporters
    def index
      # NOTE: We're paginating this in the browser.
      @exporters = Exporter.accessible_by(current_ability).order(created_at: :desc)

      add_exporter_breadcrumbs if defined?(::Hyrax)
    end

    def exporter_table
      @exporters = Exporter.accessible_by(current_ability)
      @exporters = @exporters.where(exporter_table_search) if exporter_table_search.present?
      # Count the filtered relation before applying pagination so the UI receives
      # the total number of matching exporters, not just the total number of exporters.
      filtered_count = @exporters.count
      @exporters = @exporters.order(table_order).page(table_page).per(table_per_page)
      respond_to do |format|
        format.json { render json: format_exporters(@exporters, filtered_count) }
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
      return unless defined?(::Hyrax)
      add_exporter_breadcrumbs
      add_breadcrumb t(:'bulkrax.headings.new_exporter')
    end

    # GET /exporters/1/edit
    def edit
      if defined?(::Hyrax)
        add_exporter_breadcrumbs
        add_breadcrumb @exporter.name, bulkrax.exporter_path(@exporter.id)
        add_breadcrumb t(:'bulkrax.headings.edit_exporter')
      end

      # Correctly populate export_source_collection input
      @collection = Bulkrax.object_factory.find(@exporter.export_source) if @exporter.export_source.present? && @exporter.export_from == 'collection'
    end

    # POST /exporters
    def create
      @exporter.user_id = current_user.id
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
      authorize! :read, @exporter
      send_content
    end

    private

    # Only allow a trusted parameters through.
    def exporter_params
      params[:exporter][:export_source] = params[:exporter]["export_source_#{params[:exporter][:export_from]}".to_sym]
      if params[:exporter][:date_filter] == "1"
        params.fetch(:exporter).permit(:name, :export_source, :export_from, :export_type, :generated_metadata,
                                       :include_thumbnails, :parser_klass, :limit, :start_date, :finish_date, :work_visibility,
                                       :workflow_status, field_mapping: {})
      else
        params.fetch(:exporter).permit(:name, :export_source, :export_from, :export_type, :generated_metadata,
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
      add_breadcrumb t(:'bulkrax.headings.exporters'), bulkrax.exporters_path
    end

    # Download methods

    def file_path
      "#{@exporter.exporter_export_zip_path}/#{params['exporter']['exporter_export_zip_files']}"
    end
  end
end
