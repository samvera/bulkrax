# frozen_string_literal: true

module Bulkrax
  ##
  # Formats validation data from CsvValidationService into the structure
  # expected by the importers_stepper.js frontend component.
  #
  # This service acts as a presentation layer, transforming raw validation data
  # into a structured response with proper status messages, severity levels,
  # and formatted issue lists that the JavaScript can render correctly.
  #
  # @example Basic usage
  #   validation_data = CsvValidationService.validate(csv_file: file, zip_file: zip)
  #   formatted_response = StepperResponseFormatter.format(validation_data)
  #   render json: formatted_response
  #
  # @example Error response
  #   error_response = StepperResponseFormatter.error(message: "Unable to process files")
  #   render json: error_response, status: :ok
  #
  # rubocop:disable Metrics/ClassLength
  class StepperResponseFormatter
    # Format validation data for the stepper frontend
    #
    # @param data [Hash] Raw validation data from CsvValidationService containing:
    #   - headers: Array of CSV column names
    #   - missingRequired: Array of missing required fields
    #   - unrecognized: Array of unrecognized column names
    #   - rowCount: Total number of data rows
    #   - isValid: Boolean indicating validation success
    #   - hasWarnings: Boolean indicating presence of warnings
    #   - collections: Array of collection items with id, title, type, parentIds (array)
    #   - works: Array of work items with id, title, type, parentIds (array)
    #   - fileSets: Array of file set items
    #   - totalItems: Total count of items
    #   - fileReferences: Count of file references
    #   - missingFiles: Array of missing file names
    #   - foundFiles: Count of found files
    #   - zipIncluded: Boolean indicating if zip was provided
    # @return [Hash] Formatted response ready for JSON rendering
    def self.format(data)
      new(data).format
    end

    # Generate an error response for validation failures
    #
    # @param message [String] Error message to display
    # @param summary [String] Optional summary (defaults to standard message)
    # @return [Hash] Error response structure
    def self.error(message: "Unable to process files for validation", summary: nil)
      {
        totalItems: 0,
        collections: [],
        works: [],
        fileSets: [],
        isValid: false,
        hasWarnings: false,
        messages: {
          validationStatus: {
            severity: 'error',
            icon: 'fa-times-circle',
            title: 'Validation Failed',
            summary: summary || message,
            details: 'Critical errors must be fixed before import.',
            defaultOpen: true
          },
          issues: []
        }
      }
    end

    def initialize(data)
      @data = data
    end

    # Format the validation data with messages structure
    # If data already contains a messages structure, return it as-is
    #
    # @return [Hash] Complete formatted response
    def format
      # Check if data is already formatted (has messages structure)
      return @data if already_formatted?

      # Build formatted response with messages structure
      {
        headers: @data[:headers],
        missingRequired: normalize_missing_required(@data[:missingRequired]),
        unrecognized: @data[:unrecognized],
        rowCount: @data[:rowCount],
        isValid: @data[:isValid],
        hasWarnings: @data[:hasWarnings],
        collections: @data[:collections],
        works: @data[:works],
        fileSets: @data[:fileSets],
        totalItems: @data[:totalItems],
        fileReferences: @data[:fileReferences],
        missingFiles: @data[:missingFiles],
        foundFiles: @data[:foundFiles],
        zipIncluded: @data[:zipIncluded],
        messages: build_messages
      }
    end

    private

    # Check if data is already formatted with messages structure
    #
    # @return [Boolean] true if data already has proper messages structure
    def already_formatted?
      @data.key?(:messages) &&
        @data[:messages].is_a?(Hash) &&
        @data[:messages].key?(:validationStatus)
    end

    # Normalize missingRequired to array of strings
    # Converts [{model: 'Work', field: 'title'}] to ['title']
    #
    # @param missing_required [Array] Array of hashes or strings
    # @return [Array<String>] Array of field names only
    def normalize_missing_required(missing_required)
      return [] unless missing_required

      missing_required.map do |item|
        item.is_a?(Hash) ? item[:field] : item
      end
    end

    # Build the messages structure with validationStatus and issues
    #
    # @return [Hash] Messages structure for frontend
    def build_messages
      issues = []
      issues << missing_required_issue if @data[:missingRequired]&.any?
      issues << unrecognized_fields_issue if @data[:unrecognized]&.any?
      issues << file_references_issue if @data[:fileReferences]&.positive?

      {
        validationStatus: validation_status,
        issues: issues.compact
      }
    end

    # Generate the main validation status object
    #
    # @return [Hash] Validation status with severity, icon, title, summary, details
    def validation_status
      severity, icon, title = determine_severity_level
      recognized = @data[:headers] - (@data[:unrecognized] || [])

      {
        severity: severity,
        icon: icon,
        title: title,
        summary: "#{@data[:headers].length} columns detected · #{@data[:rowCount]} records found",
        details: details_message(recognized),
        defaultOpen: true
      }
    end

    # Determine severity level based on validation state
    #
    # @return [Array<String>] [severity, icon, title]
    def determine_severity_level
      if !@data[:isValid]
        ['error', 'fa-times-circle', 'Validation Failed']
      elsif @data[:hasWarnings]
        ['warning', 'fa-exclamation-triangle', 'Validation Passed with Warnings']
      else
        ['success', 'fa-check-circle', 'Validation Passed']
      end
    end

    # Generate details message for validation status
    #
    # @param recognized [Array<String>] List of recognized field names
    # @return [String] Details message
    def details_message(recognized)
      if @data[:isValid]
        "Recognized fields: #{recognized.join(', ')}"
      else
        'Critical errors must be fixed before import.'
      end
    end

    # Format missing required fields issue
    #
    # @return [Hash] Missing required fields issue structure
    def missing_required_issue
      normalized = normalize_missing_required(@data[:missingRequired])

      {
        type: 'missing_required_fields',
        severity: 'error',
        icon: 'fa-times-circle',
        title: 'Missing Required Fields',
        count: normalized.length,
        description: 'These required columns must be added to your CSV:',
        items: normalized.map { |field| { field: field, message: 'add this column to your CSV' } },
        defaultOpen: false
      }
    end

    # Format unrecognized fields issue
    #
    # @return [Hash] Unrecognized fields issue structure
    def unrecognized_fields_issue
      {
        type: 'unrecognized_fields',
        severity: 'warning',
        icon: 'fa-exclamation-triangle',
        title: 'Unrecognized Fields',
        count: @data[:unrecognized].length,
        description: 'These columns will be ignored during import:',
        items: @data[:unrecognized].map { |field| { field: field, message: nil } },
        defaultOpen: false
      }
    end

    # Format file references issue
    #
    # @return [Hash, nil] File references issue structure or nil if not applicable
    def file_references_issue
      missing_files = @data[:missingFiles] || []

      if missing_files.any? && @data[:zipIncluded]
        missing_files_issue
      elsif !@data[:zipIncluded]
        no_zip_issue
      end
    end

    # Format issue for missing files in ZIP
    #
    # @return [Hash] Missing files issue structure
    def missing_files_issue
      missing_files = @data[:missingFiles]

      {
        type: 'file_references',
        severity: 'error',
        icon: 'fa-times-circle',
        title: 'File References',
        count: @data[:fileReferences],
        summary: "#{@data[:foundFiles]} of #{@data[:fileReferences]} files found in ZIP.",
        description: "#{missing_files.length} #{'file'.pluralize(missing_files.length)} referenced in your CSV but missing from the ZIP:",
        items: missing_files.map { |file| { field: file, message: 'missing from ZIP' } },
        defaultOpen: false
      }
    end

    # Format issue for no ZIP uploaded
    #
    # @return [Hash] No ZIP issue structure
    def no_zip_issue
      {
        type: 'file_references',
        severity: 'warning',
        icon: 'fa-exclamation-triangle',
        title: 'File References',
        count: @data[:fileReferences],
        summary: "#{@data[:fileReferences]} files referenced in CSV.",
        description: 'No ZIP file uploaded. Ensure files are accessible on the server or upload a ZIP.',
        items: [],
        defaultOpen: false
      }
    end
  end
end
# rubocop:enable Metrics/ClassLength
