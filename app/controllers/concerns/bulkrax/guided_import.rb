# frozen_string_literal: true

module Bulkrax
  # rubocop:disable Metrics/ModuleLength
  module GuidedImport
    extend ActiveSupport::Concern

    # trigger form to allow upload
    def guided_import_new
      @importer = Importer.new
      return unless defined?(::Hyrax)
      add_importer_breadcrumbs
      add_breadcrumb I18n.t('bulkrax.importer.guided_import.breadcrumb')
    end

    # AJAX endpoint to validate uploaded files
    def guided_import_validate
      set_locale_from_params

      files, error = resolve_validation_files
      return render json: error, status: :ok if error
      return render json: StepperResponseFormatter.error(message: I18n.t('bulkrax.importer.guided_import.validation.no_files_uploaded')), status: :ok unless files.any?

      csv_file, zip_file = find_csv_and_zip(files)

      unless csv_file
        return render json: StepperResponseFormatter.error(message: I18n.t('bulkrax.importer.guided_import.validation.no_csv_uploaded')), status: :ok unless zip_file

        csv_file, error = extract_csv_from_zip(zip_file)
        return render json: error, status: :ok if error
      end

      admin_set_id = params[:importer]&.[](:admin_set_id)
      render json: StepperResponseFormatter.format(run_validation(csv_file, zip_file, admin_set_id: admin_set_id)), status: :ok
    ensure
      close_file_handles(files)
    end

    def guided_import_create
      files = nil
      files = resolve_create_files
      return render_invalid_uploaded_files_response if params[:uploaded_files].present? && files.empty?

      @importer = Importer.new(guided_import_params)
      @importer.parser_klass = 'Bulkrax::CsvParser'
      @importer.user = current_user if respond_to?(:current_user) && current_user.present?
      apply_guided_import_field_mapping

      if @importer.save
        write_guided_import_files(files)
        Bulkrax::ImporterJob.perform_later(@importer.id)

        respond_to do |format|
          format.html { redirect_to bulkrax.importers_path, notice: I18n.t('bulkrax.importer.guided_import.flash.import_started') }
          format.json { render json: { success: true, importer_id: @importer.id }, status: :created }
        end
      else
        respond_to do |format|
          format.html { render :guided_import_new, status: :unprocessable_entity }
          format.json { render json: { errors: @importer.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    ensure
      close_file_handles(files)
    end

    # Serve demo scenario fixtures for frontend testing
    def guided_import_demo_scenarios
      return head :not_found unless Bulkrax.config.guided_import_demo_scenarios_enabled

      file_path = Bulkrax::Engine.root.join('lib', 'bulkrax', 'data', 'demo_scenarios.json')
      if File.exist?(file_path)
        render json: File.read(file_path), status: :ok
      else
        render json: { error: I18n.t('bulkrax.importer.guided_import.flash.demo_not_available') }, status: :not_found
      end
    end

    private

    # Resolves files for validation from either a server-side file path, pre-uploaded Hyrax files, or direct upload params
    # @return [Array<(Array<File>, nil)>] on success, a tuple of [files, nil]
    # @return [Array<(nil, Hash)>] on error, a tuple of [nil, error_response]
    def resolve_validation_files
      if import_via_file_path?
        return [nil, StepperResponseFormatter.error(message: I18n.t('bulkrax.importer.guided_import.validation.file_path_not_exist'))] unless File.exist?(import_file_path)

        [[File.open(import_file_path)], nil]
      elsif params[:uploaded_files].present?
        resolve_hyrax_uploaded_files
      else
        files = params[:importer]&.[](:parser_fields)&.[](:files) || []
        files = [files] unless files.is_a?(Array)
        [files.compact, nil]
      end
    end

    # Loads files from Hyrax::UploadedFile IDs (used by chunked upload flow).
    # Scoped to current_user to prevent accessing another user's uploads.
    def resolve_hyrax_uploaded_files
      uploads = uploaded_files_scope
      return [nil, StepperResponseFormatter.error(message: 'No uploaded files found for the given IDs')] if uploads.empty?

      files = uploads.filter_map do |u|
        path = u.file&.path
        next nil unless path && File.exist?(path)
        File.open(path)
      end
      [files, nil]
    rescue StandardError => e
      Rails.logger.error("Bulkrax: error loading Hyrax uploaded files: #{e.class}: #{e.message}")
      Rails.logger.debug { e.full_message }
      [nil, StepperResponseFormatter.error(message: 'Failed to load uploaded files')]
    end

    def uploaded_files_scope
      return [] unless defined?(::Hyrax)

      base = Hyrax::UploadedFile.where(id: params[:uploaded_files])
      if respond_to?(:current_user) && current_user.present?
        base.where(user_id: current_user.id)
      else
        base.none
      end
    end

    def render_invalid_uploaded_files_response
      respond_to do |format|
        format.html { render :guided_import_new, status: :unprocessable_entity }
        format.json { render json: { errors: ['No valid uploaded files found'] }, status: :unprocessable_entity }
      end
    end

    # Scans the given files for a CSV and a ZIP by file extension
    # @param files [Array<File, ActionDispatch::Http::UploadedFile>] the resolved files to search
    # @return [Array<(File, nil), (nil, File), (File, File), (nil, nil)>] a tuple of [csv_file, zip_file]; either may be nil
    def find_csv_and_zip(files)
      csv_file = files.find { |f| filename_for(f)&.end_with?('.csv') }
      zip_file = files.find { |f| filename_for(f)&.end_with?('.zip') }
      [csv_file, zip_file]
    end

    # Returns a filename from any file-like object (ActionDispatch upload, File, or Tempfile)
    def filename_for(file)
      if file.respond_to?(:original_filename)
        file.original_filename
      elsif file.respond_to?(:path)
        file.path
      end
    end

    # Opens a ZIP and extracts the CSV content into a StringIO while the archive is open
    # @param zip_file [File] the ZIP file to search
    # @return [Array<(StringIO, nil)>] on success, a tuple of [csv_file, nil]
    # @return [Array<(nil, Hash)>] on error, a tuple of [nil, error_response]
    def extract_csv_from_zip(zip_file)
      csv_file = nil
      error = nil
      Zip::File.open(zip_file.path) do |zip|
        result = find_csv_in_zip(zip)
        if result.is_a?(Hash) && result[:messages]
          error = result
        elsif result
          csv_file = StringIO.new(result.get_input_stream.read)
        end
      end
      [csv_file, error]
    end

    # Runs validation via the real service, or returns mock data in DEMO_MODE
    # Start demo server with: DEMO_MODE=true bin/web
    # @param csv_file [File, StringIO] the CSV to validate
    # @param zip_file [File, nil] an optional ZIP containing file attachments
    # @param admin_set_id [String, nil] optional admin set ID for validation context
    # @return [Hash] validation result data
    def run_validation(csv_file, zip_file, admin_set_id: nil)
      if ENV['DEMO_MODE'] == 'true'
        generate_validation_response(csv_file, zip_file)
      else
        CsvValidationService.validate(csv_file: csv_file, zip_file: zip_file, admin_set_id: admin_set_id)
      end
    end

    # Finds a CSV entry in a ZIP by traversing directory levels, preferring the shallowest
    # @param zip [Zip::File] the open ZIP archive to search
    # @return [Zip::Entry] the CSV entry on success
    # @return [Hash] an error response hash if no CSV is found or multiple CSVs are ambiguous
    def find_csv_in_zip(zip)
      csv_entries = group_entries_by_directory_level(zip)

      return StepperResponseFormatter.error(message: I18n.t('bulkrax.importer.guided_import.validation.no_csv_in_zip')) if csv_entries.empty?

      csv_by_depth = get_directory_depth_for_each_csv(csv_entries)
      csvs_at_level = determine_csvs_at_shallowest_level(csv_by_depth)

      csvs_by_directory = csvs_at_level.group_by { |entry| File.dirname(entry.name) }
      csvs_by_directory.each do |_dir, csvs|
        return StepperResponseFormatter.error(message: I18n.t('bulkrax.importer.guided_import.validation.multiple_csv_same_dir')) if csvs.count > 1
      end

      return StepperResponseFormatter.error(message: I18n.t('bulkrax.importer.guided_import.validation.multiple_csv_same_level')) if csvs_at_level.size > 1

      csvs_at_level.first
    end

    def group_entries_by_directory_level(zip)
      zip.select { |entry| entry.name.end_with?('.csv') && !entry.directory? }
    end

    def get_directory_depth_for_each_csv(entries)
      entries.group_by { |entry| entry.name.count('/') }
    end

    def determine_csvs_at_shallowest_level(csv_by_depth)
      shallowest_depth = csv_by_depth.keys.min
      csv_by_depth[shallowest_depth]
    end

    def resolve_create_files
      if params[:uploaded_files].present?
        uploads = uploaded_files_scope
        uploads.filter_map do |u|
          path = u.file&.path
          next nil unless path && File.exist?(path)
          File.open(path)
        end
      else
        extract_uploaded_files
      end
    end

    def close_file_handles(files)
      return unless files.is_a?(Array)
      files.each { |f| f.close if f.respond_to?(:close) }
    end

    def extract_uploaded_files
      files_param = params[:importer]&.[](:parser_fields)&.[](:files)
      return [] if files_param.blank?

      files_param.is_a?(Array) ? files_param.compact : [files_param].compact
    end

    def guided_import_params
      params.require(:importer).permit(
        :name,
        :admin_set_id,
        :limit,
        parser_fields: [:visibility, :rights_statement, :override_rights_statement, :import_file_path, :file_style]
      )
    end

    def apply_guided_import_field_mapping
      @importer.field_mapping = Bulkrax.field_mappings['Bulkrax::CsvParser']
    end

    def write_guided_import_files(files)
      csv_file, zip_file = find_csv_and_zip(files)

      csv_path = write_file_if_present(csv_file)
      zip_path = write_file_if_present(zip_file)

      return unless csv_path || zip_path

      # Determine import_file_path: prefer CSV, fallback to ZIP
      @importer.parser_fields['import_file_path'] = csv_path || zip_path
      @importer.parser_fields['attachments_zip_path'] = zip_path if zip_path && csv_path

      @importer.save
    rescue StandardError => e
      Rails.logger.error("Bulkrax::GuidedImport#write_guided_import_files failed: #{e.message}")
      raise
    end

    def write_file_if_present(file)
      return nil unless file

      if file.respond_to?(:original_filename)
        @importer.parser.write_import_file(file)
      else
        dest_path = File.join(@importer.parser.path_for_import, File.basename(file.path))
        FileUtils.cp(file.path, dest_path)
        dest_path
      end
    end

    # rubocop:disable Metrics/MethodLength
    # Hardcoded mock response generator for demo mode
    def generate_validation_response(_csv_file, zip_file)
      # Generate mock collections
      collections = [
        { id: 'col-1', title: 'Historical Photographs Collection', type: 'collection', parentIds: [], childrenIds: ['work-shared-1'] },
        { id: 'col-2', title: 'Manuscripts & Letters', type: 'collection', parentIds: [], childrenIds: [] },
        { id: 'col-3', title: 'Audio Recordings', type: 'collection', parentIds: [], childrenIds: ['work-shared-2'] }
      ]

      # Generate mock works
      works = []
      189.times do |i|
        parent_ids = if i < 75
                       ['col-1']
                     elsif i < 140
                       ['col-2']
                     elsif i < 189
                       ['col-3']
                     end

        works << {
          id: "work-#{i + 1}",
          title: "Work #{i + 1}",
          type: 'work',
          parentIds: parent_ids
        }
      end

      # Multi-parent examples
      works << { id: 'work-shared-1', title: 'Cross-Collection Photograph', type: 'work', parentIds: ['col-1', 'col-2'] }
      works << { id: 'work-shared-2', title: 'Interdisciplinary Recording', type: 'work', parentIds: ['col-2', 'col-3'] }

      # Generate mock file sets
      file_sets = []
      55.times do |i|
        file_sets << {
          id: "fs-#{i + 1}",
          title: "FileSet #{i + 1}",
          type: 'file_set'
        }
      end

      # Mock headers with one unrecognized field
      headers = ['source_identifier', 'title', 'creator', 'model', 'parents', 'children', 'file', 'description', 'date_created', 'legacy_id', 'subject']
      unrecognized = ['legacy_id']
      missing_required = []
      missing_files = ['photo_087.tiff', 'letter_scan_12.pdf', 'recording_03.wav']
      zip_included = zip_file.present?

      {
        headers: headers,
        missingRequired: missing_required,
        unrecognized: unrecognized,
        rowCount: 247,
        isValid: true,
        hasWarnings: true,
        collections: collections,
        works: works,
        fileSets: file_sets,
        totalItems: collections.length + works.length + file_sets.length,
        fileReferences: 55,
        missingFiles: missing_files,
        foundFiles: 52,
        zipIncluded: zip_included,
        messages: build_validation_messages(
          headers: headers, unrecognized: unrecognized, missing_required: missing_required,
          missing_files: missing_files, zip_included: zip_included, row_count: 247,
          is_valid: true, has_warnings: true, file_references: 55
        )
      }
    end
    # rubocop:enable Metrics/MethodLength

    # Builds the structured messages hash from validation results.
    # @param results [Hash] with keys: headers, unrecognized, missing_required,
    #   missing_files, zip_included, row_count, is_valid, has_warnings, file_references
    def build_validation_messages(results)
      issues = []
      issues << missing_required_issue(results[:missing_required]) if results[:missing_required]&.any?
      issues << unrecognized_fields_issue(results[:unrecognized]) if results[:unrecognized]&.any?
      issues << file_references_issue(results) if results[:file_references]&.positive?

      {
        validationStatus: validation_status(results),
        issues: issues.compact
      }
    end

    def validation_status(results)
      severity, icon, title = validation_status_level(results[:is_valid], results[:has_warnings])
      recognized = results[:headers] - (results[:unrecognized] || [])

      {
        severity: severity,
        icon: icon,
        title: title,
        summary: I18n.t('bulkrax.importer.guided_import.validation.columns_detected', columns: results[:headers].length, records: results[:row_count]),
        details: results[:is_valid] ? I18n.t('bulkrax.importer.guided_import.validation.recognized_fields', fields: recognized.join(', ')) : I18n.t('bulkrax.importer.guided_import.validation.critical_errors'),
        defaultOpen: true
      }
    end

    def validation_status_level(is_valid, has_warnings)
      if !is_valid
        ['error', 'fa-times-circle', I18n.t('bulkrax.importer.guided_import.validation.failed')]
      elsif has_warnings
        ['warning', 'fa-exclamation-triangle', I18n.t('bulkrax.importer.guided_import.validation.passed_warnings')]
      else
        ['success', 'fa-check-circle', I18n.t('bulkrax.importer.guided_import.validation.passed')]
      end
    end

    def missing_required_issue(missing_required)
      {
        type: 'missing_required_fields',
        severity: 'error',
        icon: 'fa-times-circle',
        title: I18n.t('bulkrax.importer.guided_import.validation.missing_required_title'),
        count: missing_required.length,
        description: I18n.t('bulkrax.importer.guided_import.validation.missing_required_desc'),
        items: missing_required.map { |field| { field: field, message: I18n.t('bulkrax.importer.guided_import.validation.missing_required_hint') } },
        defaultOpen: false
      }
    end

    def unrecognized_fields_issue(unrecognized)
      {
        type: 'unrecognized_fields',
        severity: 'warning',
        icon: 'fa-exclamation-triangle',
        title: I18n.t('bulkrax.importer.guided_import.validation.unrecognized_title'),
        count: unrecognized.length,
        description: I18n.t('bulkrax.importer.guided_import.validation.unrecognized_desc'),
        items: unrecognized.map { |field| { field: field, message: nil } },
        defaultOpen: false
      }
    end

    # rubocop:disable Metrics/MethodLength
    def file_references_issue(results)
      file_references = results[:file_references]
      missing_files = results[:missing_files] || []
      found_files = file_references - missing_files.length

      if missing_files.any? && results[:zip_included]
        {
          type: 'file_references',
          severity: 'warning',
          icon: 'fa-info-circle',
          title: I18n.t('bulkrax.importer.guided_import.validation.file_references_title'),
          count: file_references,
          summary: I18n.t('bulkrax.importer.guided_import.validation.files_found_in_zip', found: found_files, total: file_references),
          description: I18n.t('bulkrax.importer.guided_import.validation.files_missing_from_zip', count: missing_files.length, files_word: 'file'.pluralize(missing_files.length)),
          items: missing_files.map { |file| { field: file, message: I18n.t('bulkrax.importer.guided_import.validation.missing_from_zip') } },
          defaultOpen: false
        }
      elsif !results[:zip_included]
        {
          type: 'file_references',
          severity: 'warning',
          icon: 'fa-exclamation-triangle',
          title: I18n.t('bulkrax.importer.guided_import.validation.file_references_title'),
          count: file_references,
          summary: I18n.t('bulkrax.importer.guided_import.validation.files_referenced', count: file_references),
          description: I18n.t('bulkrax.importer.guided_import.validation.no_zip_desc'),
          items: [],
          defaultOpen: false
        }
      end
    end # rubocop:enable Metrics/MethodLength

    def import_via_file_path?
      import_file_path.present?
    end

    def import_file_path
      @file_path ||= params[:importer]&.[](:parser_fields)&.[](:import_file_path)
    end

    def set_locale_from_params
      I18n.locale = params[:locale] if params[:locale].present? && I18n.available_locales.include?(params[:locale].to_sym)
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
