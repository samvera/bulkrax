# frozen_string_literal: true

module Bulkrax
  # rubocop:disable Metrics/ClassLength
  class ImportersController < ::Bulkrax::ApplicationController
    include Hyrax::ThemedLayoutController if Bulkrax.hyrax_loaded?
    include Bulkrax::DownloadBehavior
    include Bulkrax::API
    include Bulkrax::DatatablesBehavior
    include Bulkrax::ValidationHelper
    include Bulkrax::ImporterFileHandler

    protect_from_forgery unless: -> { api_request? }
    # Authentication, record loading and authorization for every action.
    before_action { authenticate_and_authorize!(Bulkrax::Importer, :can_import_works?) }
    with_themed_layout 'dashboard' if Bulkrax.hyrax_loaded?

    # GET /importers
    def index
      # NOTE: We're paginating this in the browser.
      if api_request?
        # TODO(#1237): Scope API index by token owner once token-to-user wiring
        # is in place. Until then, API clients see all importers
        # to preserve backward-compatibility with existing API consumers.
        @importers = Importer.order(created_at: :desc).all
        json_response('index')
      elsif Bulkrax.hyrax_loaded?
        add_importer_breadcrumbs
      end
    end

    def importer_table
      order = table_order.presence || Arel.sql('last_imported_at DESC NULLS LAST')
      # TODO(#1237): API requests bypass ownership scoping here too.
      @importers = if api_request?
                     Importer.all
                   else
                     Importer.accessible_by(current_ability)
                   end
      @importers = @importers.where(importer_table_search) if importer_table_search.present?
      # Count the filtered relation before applying pagination so the UI receives
      # the total number of matching importers, not just the total number of importers.
      filtered_count = @importers.count
      @importers = @importers.order(order).page(table_page).per(table_per_page)
      respond_to do |format|
        format.json { render json: format_importers(@importers, filtered_count) }
      end
    end

    # GET /importers/1
    def show
      if api_request?
        json_response('show')
      elsif Bulkrax.hyrax_loaded?
        add_importer_breadcrumbs
        add_breadcrumb @importer.name
      end
      @first_entry = @importer.entries.first
    end

    def entry_table
      @entries = @importer.entries.order(table_order).page(table_page).per(table_per_page)
      @entries = @entries.where(entry_table_search) if entry_table_search.present?
      respond_to do |format|
        format.json { render json: format_entries(@entries, @importer) }
      end
    end

    # GET /importers/new
    def new
      if api_request?
        json_response('new')
      elsif Bulkrax.hyrax_loaded?
        add_importer_breadcrumbs
        add_breadcrumb t(:'bulkrax.headings.new_importer')
      end
    end

    # GET /importers/sample_csv_file
    def sample_csv_file
      admin_set_id = params[:admin_set_id].presence
      sample = Bulkrax::CsvParser.generate_template(models: 'all', output: 'file', admin_set_id: admin_set_id)
      send_file sample, filename: File.basename(sample), type: 'text/csv', disposition: 'attachment'
    rescue StandardError => e
      flash[:error] = "Unable to generate sample CSV file: #{e.message}"
      redirect_back fallback_location: bulkrax.importers_path
    end

    # GET /importers/1/edit
    def edit
      if api_request?
        json_response('edit')
      elsif Bulkrax.hyrax_loaded?
        add_importer_breadcrumbs
        add_breadcrumb @importer.name, bulkrax.importer_path(@importer.id)
        add_breadcrumb t(:'bulkrax.headings.edit_importer')
      end
    end

    # POST /importers
    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Metrics/AbcSize
    def create
      if api_request?
        return return_json_response unless valid_create_params?
        # authenticate_and_authorize! doesn't build for API requests; build it here
        @importer ||= Importer.new(importer_params)
      end
      @importer.user_id = current_user.id
      uploads = uploaded_files_scope
      file = file_param
      cloud_files = cloud_params

      field_mapping_params
      @importer.validate_only = true if params[:commit] == 'Create and Validate'
      # the following line is needed to handle updating remote files of a FileSet
      # on a new import otherwise it only gets updated during the update path
      @importer.parser_fields['update_files'] = true if params[:commit] == 'Create and Import'

      # Reject an unsafe cloud selection before the importer is ever
      # persisted, rather than after save when a row would already exist.
      preflight_cloud_files!(cloud_files)

      if @importer.save
        return render_create_failure if files_for_import(file, cloud_files, uploads) && !@importer.save
        dispatch_cloud_downloads!

        if params[:commit] == 'Create and Import'
          Bulkrax::ImporterJob.send(@importer.parser.perform_method, @importer.id)
          render_request('Importer was successfully created and import has been queued.')
        elsif params[:commit] == 'Create and Validate'
          Bulkrax::ImporterJob.send(@importer.parser.perform_method, @importer.id)
          render_request('Importer validation completed. Please review and choose to either Continue with or Discard the import.', true)
        else
          render_request('Importer was successfully created.')
        end
      else
        render_create_failure
      end
    rescue Bulkrax::UnsafeCloudSourceError, Bulkrax::UnsafePathError => e
      reject_unsafe_cloud_files(e)
    end
    # rubocop:enable Metrics/AbcSize

    # PATCH/PUT /importers/1
    # # @todo refactor so as to not need to disable rubocop
    # rubocop:disable all
    def update
      if api_request?
        return return_json_response unless valid_update_params?
      end
      uploads = uploaded_files_scope
      file = file_param
      cloud_files = cloud_params

      # Skipped during a continue
      field_mapping_params if params[:importer][:parser_fields].present?

      # Assign the proposed attributes in memory first, so an unsafe cloud
      # selection is rejected before anything is persisted; the rescue
      # below then leaves the importer's persisted attributes untouched.
      @importer.assign_attributes(importer_params)
      preflight_cloud_files!(cloud_files)

      if @importer.save
        return render_update_failure if files_for_import(file, cloud_files, uploads) && !@importer.save
        return render_update_failure if params[:commit] != 'Update Importer' && !set_files_parser_fields
        dispatch_cloud_downloads!

        # do not perform the import
        unless params[:commit] == 'Update Importer'
          Bulkrax::ImporterJob.send(@importer.parser.perform_method, @importer.id, update_harvest)
        end
        if api_request?
          json_response('updated', :ok, 'Importer was successfully updated.')
        else
          redirect_to importers_path, notice: 'Importer was successfully updated.'
        end
      else
        render_update_failure
      end
    rescue Bulkrax::UnsafeCloudSourceError, Bulkrax::UnsafePathError => e
      reject_unsafe_cloud_files(e)
    end
    # rubocop:enable all
    # rubocop:enable Metrics/MethodLength

    # DELETE /importers/1
    def destroy
      @importer.destroy
      if api_request?
        json_response('destroy', :ok, notice: 'Importer was successfully destroyed.')
      else
        redirect_to importers_url, notice: 'Importer was successfully destroyed.'
      end
    end

    # PUT /importers/1
    def continue
      params[:importer] = { name: @importer.name }
      @importer.validate_only = false
      update
    end

    # GET /importer/1/upload_corrected_entries
    def upload_corrected_entries
      return unless Bulkrax.hyrax_loaded?
      add_breadcrumb t(:'hyrax.controls.home'), main_app.root_path
      add_breadcrumb t(:'hyrax.dashboard.breadcrumbs.admin'), hyrax.dashboard_path
      add_breadcrumb t(:'bulkrax.headings.importers'), bulkrax.importers_path
      add_breadcrumb @importer.name, bulkrax.importer_path(@importer.id)
      add_breadcrumb t(:'bulkrax.headings.upload_corrected_entries_action')
    end

    # POST /importer/1/upload_corrected_entries_file
    def upload_corrected_entries_file
      file = params[:importer][:parser_fields].delete(:file)
      if file.present?
        @importer[:parser_fields]['partial_import_file_path'] = @importer.parser.write_partial_import_file(file)
        @importer.save
        Bulkrax::ImporterJob.perform_later(@importer.id, true)
        redirect_to importer_path(@importer), notice: 'Corrected entries uploaded successfully.'
      else
        redirect_to importer_upload_corrected_entries_path(@importer), alert: 'Importer failed to update with new file.'
      end
    end

    def external_sets
      if list_external_sets
        render json: { base_url: params[:base_url], sets: @sets }
      else
        render json: { base_url: params[:base_url], error: "unable to pull data from #{params[:base_url]}" }
      end
    end

    def original_file
      file_type = params[:file_type]&.to_sym

      files = @importer.original_files
      if files.empty?
        redirect_to @importer, alert: 'Importer does not support file re-download or the imported file is not found on the server.'
        return
      end

      # If file_type is specified, find that specific file
      if file_type
        file = files.find { |f| f[:type] == file_type }
        if file
          send_file file[:path], filename: file[:name], disposition: 'attachment'
        else
          redirect_to @importer, alert: "File type '#{file_type}' not found."
        end
      else
        # Default behavior: send the first file (CSV) for backward compatibility
        file = files.first
        send_file file[:path], filename: file[:name], disposition: 'attachment'
      end
    end

    # GET /importers/1/export_errors
    def export_errors
      @importer.write_errored_entries_file
      send_content
    end

    private

    def importable_params
      params.except(:selected_files)
    end

    def importable_parser_fields
      params&.[](:importer)&.[](:parser_fields)&.except(:file, :entry_statuses)&.keys&. + [{ "entry_statuses" => [] }]
    end

    # Only allow a trusted parameters through.
    def importer_params
      importable_params.require(:importer).permit(
        :name,
        :admin_set_id,
        :frequency,
        :parser_klass,
        :limit,
        :validate_only,
        selected_files: {},
        field_mapping: {},
        parser_fields: [importable_parser_fields]
      )
    end

    def list_external_sets
      url = params[:base_url] || @harvester&.base_url
      setup_client(url) if url.present?

      @sets = [['All', 'all']]

      begin
        @client.list_sets.each do |s|
          @sets << [s.name, s.spec]
        end
      rescue
        return false
      end

      @sets
    end

    def file_param
      params.require(:importer).require(:parser_fields).fetch(:file) if params&.[](:importer)&.[](:parser_fields)&.[](:file)
    end

    def cloud_params
      params.permit(selected_files: {}).fetch(:selected_files).to_h if params&.[](:selected_files)
    end

    # Add the field_mapping from the Bulkrax configuration
    def field_mapping_params
      # @todo replace/append once mapping GUI is in place
      field_mapping_key = Bulkrax.parsers.map { |m| m[:class_name] if m[:class_name] == params[:importer][:parser_klass] }.compact.first
      @importer.field_mapping = Bulkrax.field_mappings[field_mapping_key] if field_mapping_key
    end

    def add_importer_breadcrumbs
      add_breadcrumb t(:'hyrax.controls.home'), main_app.root_path
      add_breadcrumb t(:'hyrax.dashboard.breadcrumbs.admin'), hyrax.dashboard_path
      add_breadcrumb t(:'bulkrax.headings.importers'), bulkrax.importers_path
    end

    def setup_client(url)
      return false if url.nil?
      headers = { from: Bulkrax.server_name }
      @client ||= OAI::Client.new(url, headers: headers, parser: 'libxml')
    end

    # Download methods

    def file_path
      @importer.errored_entries_csv_path
    end

    def download_content_type
      'text/csv'
    end

    # Reports an unsafe cloud-file batch without leaking the error's class
    # or backtrace (which could include a provider auth header) to the
    # response; `e.message` is always one of our own static, credential-free
    # strings (see Bulkrax::CloudSourceValidator / Bulkrax::SafePath).
    def reject_unsafe_cloud_files(e)
      Rails.logger.error("Bulkrax: rejected unsafe cloud file batch for importer #{@importer&.id}: #{e.class}: #{e.message}")
      if api_request?
        json_response('create', :unprocessable_entity, e.message)
      else
        flash[:error] = e.message
        redirect_back fallback_location: bulkrax.importers_path
      end
    end

    def render_create_failure
      if api_request?
        json_response('create', :unprocessable_entity)
      else
        render :new
      end
    end

    def render_update_failure
      if api_request?
        json_response('update', :unprocessable_entity, 'Something went wrong.')
      else
        render :edit
      end
    end

    def render_request(message, validate_only = false)
      if api_request?
        json_response('create', :created, message)
      else
        path = validate_only ? importer_path(@importer) : importers_path
        redirect_to path, notice: message
      end
    end

    # update methods (for commit deciphering)
    def update_harvest
      # OAI-only - selective re-harvest
      params[:commit] == 'Update and Harvest Updated Items'
    end

    # @return [Boolean] the result of the save, so the caller can treat a
    #   failure here like an ordinary validation failure
    def set_files_parser_fields
      @importer.parser_fields['update_files'] =
        @importer.parser_fields['replace_files'] =
          @importer.parser_fields['remove_and_rerun'] =
            @importer.parser_fields['metadata_only'] = false
      if params[:commit] == 'Update Metadata and Files'
        @importer.parser_fields['update_files'] = true
      elsif params[:commit] == ('Update and Replace Files' || 'Update and Re-Harvest All Items')
        @importer.parser_fields['replace_files'] = true
      elsif params[:commit] == 'Remove and Rerun'
        @importer.parser_fields['remove_and_rerun'] = true
      elsif params[:commit] == 'Update and Harvest Updated Items'
        return true
      else
        @importer.parser_fields['metadata_only'] = true
      end
      @importer.save
    end
  end
  # rubocop:enable Metrics/ClassLength
end
