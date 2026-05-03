# frozen_string_literal: true

module Bulkrax
  # rubocop:disable Metrics/ClassLength
  class ImportersController < ::Bulkrax::ApplicationController
    include Hyrax::ThemedLayoutController if defined?(::Hyrax)
    include Bulkrax::DownloadBehavior
    include Bulkrax::API
    include Bulkrax::DatatablesBehavior
    include Bulkrax::ValidationHelper
    include Bulkrax::ImporterFileHandler

    protect_from_forgery unless: -> { api_request? }
    before_action :token_authenticate!, if: -> { api_request? }, only: [:create, :update, :delete]
    before_action :authenticate_user!, unless: -> { api_request? }
    # load_and_authorize_resource covers standard CRUD member actions for
    # non-API requests.  Actions that use :importer_id rather than :id, or
    # that are collection-scoped, are excluded and handled by separate
    # before_actions below.
    load_and_authorize_resource class: 'Bulkrax::Importer',
                                instance_name: :importer,
                                except: [:index, :importer_table, :sample_csv_file, :external_sets,
                                         :continue, :upload_corrected_entries, :upload_corrected_entries_file,
                                         :export_errors, :original_file],
                                unless: -> { api_request? }
    # For API requests, fall back to simple find so existing consumers are
    # unaffected while the token-to-user wiring is not yet implemented.
    before_action :set_importer_for_api,
                  only: [:show, :entry_table, :edit, :update, :destroy, :original_file],
                  if: -> { api_request? }
    # Actions that reference importers by :importer_id (not :id)
    before_action :load_and_authorize_importer_by_importer_id,
                  only: [:continue, :upload_corrected_entries, :upload_corrected_entries_file, :export_errors, :original_file]
    with_themed_layout 'dashboard' if defined?(::Hyrax)

    # GET /importers
    def index
      # NOTE: We're paginating this in the browser.
      if api_request?
        # TODO: Scope API index by token owner once token-to-user wiring is in
        # place.  Tracked in [ISSUE].  Until then, API clients see all importers
        # to preserve backward-compatibility with existing API consumers.
        @importers = Importer.order(created_at: :desc).all
        json_response('index')
      elsif defined?(::Hyrax)
        add_importer_breadcrumbs
      end
    end

    def importer_table
      order = table_order.presence || Arel.sql('last_imported_at DESC NULLS LAST')
      # TODO: API requests bypass ownership scoping here too; see index TODO.
      @importers = if api_request?
                     Importer.all
                   else
                     Importer.accessible_by(current_ability)
                   end
      @importers = @importers.order(order).page(table_page).per(table_per_page)
      @importers = @importers.where(importer_table_search) if importer_table_search.present?
      respond_to do |format|
        format.json { render json: format_importers(@importers) }
      end
    end

    # GET /importers/1
    def show
      if api_request?
        json_response('show')
      elsif defined?(::Hyrax)
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
      elsif defined?(::Hyrax)
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
      elsif defined?(::Hyrax)
        add_importer_breadcrumbs
        add_breadcrumb @importer.name, bulkrax.importer_path(@importer.id)
        add_breadcrumb t(:'bulkrax.headings.edit_importer')
      end
    end

    # POST /importers
    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Metrics/AbcSize
    def create
      # rubocop:disable Style/IfInsideElse
      if api_request?
        return return_json_response unless valid_create_params?
        # load_and_authorize_resource is skipped for API; build the record here.
        @importer ||= Importer.new(importer_params)
      end
      uploads = uploaded_files_scope
      file = file_param
      cloud_files = cloud_params

      field_mapping_params
      @importer.validate_only = true if params[:commit] == 'Create and Validate'
      # the following line is needed to handle updating remote files of a FileSet
      # on a new import otherwise it only gets updated during the update path
      @importer.parser_fields['update_files'] = true if params[:commit] == 'Create and Import'
      if @importer.save
        files_for_import(file, cloud_files, uploads)
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
        if api_request?
          json_response('create', :unprocessable_entity)
        else
          render :new
        end
      end
      # rubocop:enable Style/IfInsideElse
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

      if @importer.update(importer_params)
        files_for_import(file, cloud_files, uploads)
        # do not perform the import
        unless params[:commit] == 'Update Importer'
          set_files_parser_fields
          Bulkrax::ImporterJob.send(@importer.parser.perform_method, @importer.id, update_harvest)
        end
        if api_request?
          json_response('updated', :ok, 'Importer was successfully updated.')
        else
          redirect_to importers_path, notice: 'Importer was successfully updated.'
        end
      else
        if api_request?
          json_response('update', :unprocessable_entity, 'Something went wrong.')
        else
          render :edit
        end
      end
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
      return unless defined?(::Hyrax)
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

    # Load @importer for API requests (no CanCan authorization — the API path
    # does not yet resolve a token to a current_user, so ownership rules cannot
    # be evaluated).
    # TODO: Remove once token-to-user wiring is complete and CanCan rules apply
    # uniformly to API requests.  Tracked in [ISSUE].
    def set_importer_for_api
      @importer = Importer.find(params[:id] || params[:importer_id])
    end

    # Load and authorize @importer for actions that identify the importer by
    # :importer_id rather than :id (e.g. continue, upload_corrected_entries).
    # Uses the action name directly so that alias_action mappings defined in
    # bulkrax_default_abilities apply (e.g. :export_errors → :read,
    # :continue → :update).
    def load_and_authorize_importer_by_importer_id
      @importer = Importer.find(params[:importer_id])
      authorize! action_name.to_sym, @importer
    end

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
        :user_id,
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
        return
      else
        @importer.parser_fields['metadata_only'] = true
      end
      @importer.save
    end
  end
  # rubocop:enable Metrics/ClassLength
end
