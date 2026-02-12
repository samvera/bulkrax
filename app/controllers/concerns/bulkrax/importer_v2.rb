# frozen_string_literal: true

# temporarily disable all rubocop checks for this file since it's a work in progress and will be fully implemented in a future PR
# rubocop:disable all
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
      response = generate_validation_response(csv_file, zip_file)
      render json: response, status: :ok
    end

    def create_v2
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

      {
        headers: headers,
        missingRequired: [], # Empty = validation passes
        unrecognized: unrecognized,
        rowCount: 247,
        isValid: true,
        hasWarnings: true, # Due to unrecognized field
        collections: collections,
        works: works,
        fileSets: file_sets,
        allItems: collections + works,
        totalItems: collections.length + works.length + file_sets.length,
        fileReferences: 55,
        missingFiles: ['photo_087.tiff', 'letter_scan_12.pdf', 'recording_03.wav'],
        foundFiles: 52,
        zipIncluded: zip_file.present?
      }
    end
  end
end
# rubocop:enable all
