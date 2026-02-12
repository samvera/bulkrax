module Bulkrax
  module ImporterV2
    extend ActiveSupport::Concern

    # trigger form to allow upload
    def new_v2
      @importer = Importer.new
      if defined?(::Hyrax)
        add_importer_breadcrumbs
        add_breadcrumb 'New Import (V2)'
      end
    end

    # AJAX endpoint to validate uploaded files
    def validate_v2
      files = params[:importer]&.[](:parser_fields)&.[](:files) || []
      files = [files] unless files.is_a?(Array)
      files = files.compact

      unless files.any?
        render json: { error: 'No file uploaded' }, status: :unprocessable_entity
        return
      end

      # Find CSV file for validation
      csv_file = files.find { |f| f.original_filename&.end_with?('.csv') }
      zip_file = files.find { |f| f.original_filename&.end_with?('.zip') }

      # If no CSV in uploaded files, check if ZIP contains CSV
      unless csv_file
        if zip_file
          csv_exists = Zip::File.open(zip_file.path) do |zip|
            zip.any? { |entry| entry.name.end_with?('.csv') }
          end
          unless csv_exists
            render json: { error: 'No CSV file found. Please upload a CSV file.' }, status: :unprocessable_entity
            return
          end
        else
          render json: { error: 'No CSV file uploaded' }, status: :unprocessable_entity
          return
        end
      end

      # Mock validation response for testing
      # TODO: Replace with actual CsvValidationService call
      # NOTE: Frontend demo scenarios are in lib/bulkrax/data/demo_scenarios.json
      response = generate_validation_response(csv_file, zip_file)
      render json: response, status: :ok
    end

    def create_v2
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

    def generate_validation_response(csv_file, zip_file)
      # Generate mock collections
      collections = [
        { id: 'col-1', title: 'Historical Photographs Collection', type: 'collection', parentId: nil },
        { id: 'col-2', title: 'Manuscripts & Letters', type: 'collection', parentId: nil },
        { id: 'col-3', title: 'Audio Recordings', type: 'collection', parentId: nil }
      ]

      # Generate mock works
      works = []
      189.times do |i|
        parent_id = if i < 75
                      'col-1'
                    elsif i < 140
                      'col-2'
                    elsif i < 189
                      'col-3'
                    else
                      nil
                    end

        works << {
          id: "work-#{i + 1}",
          title: "Work #{i + 1}",
          type: 'work',
          parentId: parent_id
        }
      end

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
      headers = ['source_identifier', 'title', 'creator', 'model', 'parents', 'file', 'description', 'date_created', 'legacy_id', 'subject']
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
          headers: headers,
          unrecognized: unrecognized,
          missing_required: missing_required,
          missing_files: missing_files,
          zip_included: zip_included,
          row_count: 247,
          is_valid: true,
          has_warnings: true,
          file_references: 55
        )
      }
    end

    def build_validation_messages(headers:, unrecognized:, missing_required:, missing_files:, zip_included:, row_count:, is_valid:, has_warnings:, file_references: 0)
      recognized_fields = headers - unrecognized
      
      messages = {
        validationStatus: {
          severity: is_valid ? (has_warnings ? 'warning' : 'success') : 'error',
          icon: is_valid ? (has_warnings ? 'fa-exclamation-triangle' : 'fa-check-circle') : 'fa-times-circle',
          title: is_valid ? (has_warnings ? 'Validation Passed with Warnings' : 'Validation Passed') : 'Validation Failed',
          summary: "#{headers.length} columns detected · #{row_count} records found",
          details: is_valid ? "Recognized fields: #{recognized_fields.join(', ')}" : 'Critical errors must be fixed before import.',
          defaultOpen: true
        },
        issues: []
      }

      # Add missing required fields issue
      if missing_required.any?
        messages[:issues] << {
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

      # Add unrecognized fields issue
      if unrecognized.any?
        messages[:issues] << {
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

      # Add file references issue
      if missing_files.any? && zip_included
        messages[:issues] << {
          type: 'file_references',
          severity: 'warning',
          icon: 'fa-info-circle',
          title: 'File References',
          count: 55,
          summary: '52 of 55 files found in ZIP.',
          description: '3 files are referenced in your CSV but missing from the ZIP:',
          items: missing_files.map { |file| { field: file, message: 'missing from ZIP' } },
          defaultOpen: false
        }
      elsif file_references > 0 && !zip_included
        # Files referenced but no ZIP uploaded
        messages[:issues] << {
          type: 'file_references',
          severity: 'warning',
          icon: 'fa-exclamation-triangle',
          title: 'File References',
          count: file_references,
          summary: "#{file_references} files referenced in CSV.",
          description: 'No ZIP file uploaded. Ensure files are accessible on the server or upload a ZIP file containing the referenced files.',
          items: [],
          defaultOpen: false
        }
      end

      messages
    end
  end
end
