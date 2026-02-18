# frozen_string_literal: true

module Bulkrax
  # rubocop:disable Metrics/ModuleLength
  module ImporterV2
    extend ActiveSupport::Concern

    # trigger form to allow upload
    def new_v2
      @importer = Importer.new
      return unless defined?(::Hyrax)
      add_importer_breadcrumbs
      add_breadcrumb 'New Import (V2)'
    end

    # AJAX endpoint to validate uploaded files
    # rubocop:disable Metrics/MethodLength
    def validate_v2
      if file_path_import?
        files = [File.open(@file_path)]
        return render json: StepperResponseFormatter.error(message: 'File path does not exist'), status: :ok if !File.exist?(@file_path)
      end

      if files.blank?
        files = params[:importer]&.[](:parser_fields)&.[](:files) || []
        files = [files] unless files.is_a?(Array)
        files = files.compact
      end

      unless files.any?
        render json: StepperResponseFormatter.error(message: 'No files uploaded'), status: :ok
        return
      end

      # Find CSV file for validation
      method = file_path_import? ? :path : :original_filename
      csv_file = files.find { |f| f.public_send(method)&.end_with?('.csv') }
      zip_file = files.find { |f| f.public_send(method)&.end_with?('.zip') }

      # If no CSV in uploaded files, check if ZIP contains CSV
      unless csv_file
        unless zip_file
          render json: StepperResponseFormatter.error(message: 'No CSV metadata file uploaded'), status: :ok
          return
        end

        error_response = nil
        Zip::File.open(zip_file.path) do |zip|
          result = find_csv_in_zip(zip)

          if result.is_a?(Hash) && result[:messages]
            error_response = result
          elsif result
            # Read the CSV content while the zip file is still open
            csv_file = StringIO.new(result.get_input_stream.read)
          end
        end

        if error_response
          render json: error_response, status: :ok
          return
        end
      end

      # Use demo mode if DEMO_MODE environment variable is set
      # Start server with: DEMO_MODE=true bin/web
      validation_data = if ENV['DEMO_MODE'] == 'true'
                          generate_validation_response(csv_file, zip_file)
                        else
                          CsvValidationService.validate(csv_file: csv_file, zip_file: zip_file)
                        end

      formatted_response = StepperResponseFormatter.format(validation_data)
      render json: formatted_response, status: :ok
    end
    # rubocop:enable Metrics/MethodLength

    def create_v2
      files = extract_uploaded_files

      @importer = Importer.new(importer_params_v2)
      @importer.parser_klass = 'Bulkrax::CsvParser'
      @importer.user = current_user if respond_to?(:current_user) && current_user.present?
      apply_field_mapping_v2

      if @importer.save
        write_files_v2(files)
        Bulkrax::ImporterJob.perform_later(@importer.id)

        respond_to do |format|
          format.html { redirect_to bulkrax.importers_path, notice: 'Import started successfully.' }
          format.json { render json: { success: true, importer_id: @importer.id }, status: :created }
        end
      else
        respond_to do |format|
          format.html { render :new_v2, status: :unprocessable_entity }
          format.json { render json: { errors: @importer.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    # Serve demo scenario fixtures for frontend testing
    def demo_scenarios_v2
      file_path = Bulkrax::Engine.root.join('lib', 'bulkrax', 'data', 'demo_scenarios.json')
      if File.exist?(file_path)
        render json: File.read(file_path), status: :ok
      else
        render json: { error: 'Demo scenarios not available' }, status: :not_found
      end
    end

    private

    # Finds CSV file in ZIP by traversing directory levels
    # Returns CSV entry object on success, or StepperResponseFormatter.error hash on error
    def find_csv_in_zip(zip)
      csv_entries = group_entries_by_directory_level(zip)

      return StepperResponseFormatter.error(message: 'No CSV files found in ZIP') if csv_entries.empty?

      csv_by_depth = get_directory_depth_for_each_csv(csv_entries)
      csvs_at_level = determine_csvs_at_shallowest_level(csv_by_depth)

      csvs_by_directory = csvs_at_level.group_by { |entry| File.dirname(entry.name) }
      csvs_by_directory.each do |_dir, csvs|
        return StepperResponseFormatter.error(message: 'Multiple CSV files found in the same directory within ZIP') if csvs.count > 1
      end

      return StepperResponseFormatter.error(message: 'Multiple CSV files found at the same level within ZIP') if csvs_at_level.size > 1

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

    def extract_uploaded_files
      files_param = params[:importer]&.[](:parser_fields)&.[](:files)
      return [] if files_param.blank?

      files_param.is_a?(Array) ? files_param.compact : [files_param].compact
    end

    def importer_params_v2
      params.require(:importer).permit(
        :name,
        :admin_set_id,
        :limit,
        parser_fields: [:visibility, :rights_statement, :override_rights_statement, :file_path]
      )
    end

    def apply_field_mapping_v2
      @importer.field_mapping = Bulkrax.field_mappings['Bulkrax::CsvParser']
    end

    def write_files_v2(files)
      csv_file = files.find { |f| f.original_filename&.end_with?('.csv') }
      zip_file = files.find { |f| f.original_filename&.end_with?('.zip') }

      csv_path = nil
      zip_path = nil
      if csv_file && zip_file
        csv_path = @importer.parser.write_import_file(csv_file)
        zip_path = @importer.parser.write_import_file(zip_file)
        @importer.parser_fields['import_file_path'] = csv_path
        @importer.parser_fields['attachments_zip_path'] = zip_path
      elsif zip_file && !csv_file
        zip_path = @importer.parser.write_import_file(zip_file)
        @importer.parser_fields['import_file_path'] = zip_path
      elsif csv_file && !zip_file
        csv_path = @importer.parser.write_import_file(csv_file)
        @importer.parser_fields['import_file_path'] = csv_path
      end

      @importer.save if csv_path || zip_path
    rescue StandardError => e
      Rails.logger.error("Bulkrax::ImporterV2#write_files_v2 failed: #{e.message}")
      raise
    end

    # rubocop:disable Metrics/MethodLength
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
        summary: "#{results[:headers].length} columns detected · #{results[:row_count]} records found",
        details: results[:is_valid] ? "Recognized fields: #{recognized.join(', ')}" : 'Critical errors must be fixed before import.',
        defaultOpen: true
      }
    end

    def validation_status_level(is_valid, has_warnings)
      if !is_valid
        ['error', 'fa-times-circle', 'Validation Failed']
      elsif has_warnings
        ['warning', 'fa-exclamation-triangle', 'Validation Passed with Warnings']
      else
        ['success', 'fa-check-circle', 'Validation Passed']
      end
    end

    def missing_required_issue(missing_required)
      {
        type: 'missing_required_fields',
        severity: 'error',
        icon: 'fa-times-circle',
        title: 'Missing Required Fields',
        count: missing_required.length,
        description: 'These required columns must be added to your CSV:',
        items: missing_required.map { |field| { field: field, message: 'add this column to your CSV' } },
        defaultOpen: false
      }
    end

    def unrecognized_fields_issue(unrecognized)
      {
        type: 'unrecognized_fields',
        severity: 'warning',
        icon: 'fa-exclamation-triangle',
        title: 'Unrecognized Fields',
        count: unrecognized.length,
        description: 'These columns will be ignored during import:',
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
          title: 'File References',
          count: file_references,
          summary: "#{found_files} of #{file_references} files found in ZIP.",
          description: "#{missing_files.length} #{'file'.pluralize(missing_files.length)} referenced in your CSV but missing from the ZIP:",
          items: missing_files.map { |file| { field: file, message: 'missing from ZIP' } },
          defaultOpen: false
        }
      elsif !results[:zip_included]
        {
          type: 'file_references',
          severity: 'warning',
          icon: 'fa-exclamation-triangle',
          title: 'File References',
          count: file_references,
          summary: "#{file_references} files referenced in CSV.",
          description: 'No ZIP file uploaded. Ensure files are accessible on the server or upload a ZIP.',
          items: [],
          defaultOpen: false
        }
      end
    end # rubocop:enable Metrics/MethodLength

    def file_path_import?
      @file_path = params[:importer]&.[](:parser_fields)&.[](:file_path)
      @file_path.present?
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
