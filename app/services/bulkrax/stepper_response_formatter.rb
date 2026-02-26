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
    #   - missingRequired: Array of hashes of missing required fields by model (e.g. {model: 'GenericWork', field: 'source_identifier'})
    #   - unrecognized: Array of unrecognized column names
    #   - rowCount: Total number of data rows
    #   - isValid: Boolean indicating validation success
    #   - hasWarnings: Boolean indicating presence of warnings
    #   - collections: Array of collection items with id, title, type, parentIds (array), childIds (array)
    #   - works: Array of work items with id, title, type, parentIds (array), childIds (array)
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
    def self.error(message: I18n.t('bulkrax.importer.guided_import.validation.unable_to_process'), summary: nil)
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
            title: I18n.t('bulkrax.importer.guided_import.validation.failed'),
            summary: summary || message,
            details: I18n.t('bulkrax.importer.guided_import.validation.critical_errors'),
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
        missingRequired: @data[:missingRequired],
        unrecognized: @data[:unrecognized],
        rowCount: @data[:rowCount],
        isValid: @data[:isValid],
        hasWarnings: @data[:hasWarnings],
        rowErrors: @data[:rowErrors],
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

    # Build the messages structure with validationStatus and issues
    #
    # @return [Hash] Messages structure for frontend
    def build_messages
      issues = []
      issues << missing_required_issue if @data[:missingRequired]&.any?
      issues << unrecognized_fields_issue if @data[:unrecognized]&.any?
      issues << file_references_issue if @data[:fileReferences]&.positive?
      issues << row_errors_issue if @data[:rowErrors]&.any?

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
      recognized = @data[:headers] - (@data[:unrecognized].keys || [])

      {
        severity: severity,
        icon: icon,
        title: title,
        summary: I18n.t('bulkrax.importer.guided_import.validation.columns_detected', columns: @data[:headers].length, records: @data[:rowCount]),
        details: details_message(recognized),
        defaultOpen: true
      }
    end

    # Determine severity level based on validation state
    #
    # @return [Array<String>] [severity, icon, title]
    def determine_severity_level
      if !@data[:isValid]
        ['error', 'fa-times-circle', I18n.t('bulkrax.importer.guided_import.validation.failed')]
      elsif @data[:hasWarnings]
        ['warning', 'fa-exclamation-triangle', I18n.t('bulkrax.importer.guided_import.validation.passed_warnings')]
      else
        ['success', 'fa-check-circle', I18n.t('bulkrax.importer.guided_import.validation.passed')]
      end
    end

    # Generate details message for validation status
    #
    # @param recognized [Array<String>] List of recognized field names
    # @return [String] Details message
    def details_message(recognized)
      if @data[:isValid]
        I18n.t('bulkrax.importer.guided_import.validation.recognized_fields', fields: recognized.join(', '))
      else
        I18n.t('bulkrax.importer.guided_import.validation.critical_errors')
      end
    end

    # Format missing required fields issue
    #
    # @return [Hash] Missing required fields issue structure
    def missing_required_issue
      only_rights_statement = @data[:missingRequired]&.all? { |h| h[:field].to_s == 'rights_statement' }

      if only_rights_statement
        {
          type: 'missing_required_fields',
          severity: 'warning',
          icon: 'fa-exclamation-triangle',
          title: I18n.t('bulkrax.importer.guided_import.validation.missing_required_title'),
          count: @data[:missingRequired].length,
          description: I18n.t('bulkrax.importer.guided_import.validation.missing_rights_desc'),
          items: @data[:missingRequired],
          defaultOpen: false
        }
      else
        {
          type: 'missing_required_fields',
          severity: 'error',
          icon: 'fa-times-circle',
          title: I18n.t('bulkrax.importer.guided_import.validation.missing_required_title'),
          count: @data[:missingRequired].length,
          description: I18n.t('bulkrax.importer.guided_import.validation.missing_required_desc'),
          items: @data[:missingRequired],
          defaultOpen: false
        }
      end
    end

    # Format unrecognized fields issue
    #
    # @return [Hash] Unrecognized fields issue structure
    def unrecognized_fields_issue
      {
        type: 'unrecognized_fields',
        severity: 'warning',
        icon: 'fa-exclamation-triangle',
        title: I18n.t('bulkrax.importer.guided_import.validation.unrecognized_title'),
        count: @data[:unrecognized].length,
        description: I18n.t('bulkrax.importer.guided_import.validation.unrecognized_desc'),
        items: unrecognized_fields_issue_items,
        defaultOpen: false
      }
    end

    def unrecognized_fields_issue_items
      @data[:unrecognized].partition(&:last)
                          .flatten(1)
                          .map { |field| { field: field.first, message: field.last ? I18n.t('bulkrax.importer.guided_import.validation.did_you_mean', suggestion: field.last) : nil } }
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
        severity: 'warning',
        icon: 'fa-info-circle',
        title: I18n.t('bulkrax.importer.guided_import.validation.file_references_title'),
        count: @data[:fileReferences],
        summary: I18n.t('bulkrax.importer.guided_import.validation.files_found_in_zip', found: @data[:foundFiles], total: @data[:fileReferences]),
        description: I18n.t('bulkrax.importer.guided_import.validation.files_missing_from_zip', count: missing_files.length, files_word: 'file'.pluralize(missing_files.length)),
        items: missing_files.map { |file| { field: file, message: I18n.t('bulkrax.importer.guided_import.validation.missing_from_zip') } },
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
        title: I18n.t('bulkrax.importer.guided_import.validation.file_references_title'),
        count: @data[:fileReferences],
        summary: I18n.t('bulkrax.importer.guided_import.validation.files_referenced', count: @data[:fileReferences]),
        description: I18n.t('bulkrax.importer.guided_import.validation.no_zip_desc'),
        items: [],
        defaultOpen: false
      }
    end

    def row_errors_issue
      filtered = filtered_row_errors
      return nil if filtered.empty?

      severity = filtered.any? { |e| e[:severity] == 'error' } ? 'error' : 'warning'
      icon = severity == 'error' ? 'fa-times-circle' : 'fa-exclamation-triangle'

      {
        type: 'row_level_errors',
        severity: severity,
        icon: icon,
        title: I18n.t('bulkrax.importer.guided_import.stepper_response_formatter.row_errors_issue.title'),
        count: filtered.length,
        description: I18n.t('bulkrax.importer.guided_import.stepper_response_formatter.row_errors_issue.description'),
        items: row_error_items(filtered),
        defaultOpen: false
      }
    end

    def filtered_row_errors
      missing_required_columns = @data[:missingRequired]&.map { |h| h[:field].to_s } || []
      @data[:rowErrors].reject { |e| missing_required_columns.include?(e[:column].to_s) }
    end

    def row_error_items(errors)
      errors.map do |error|
        {
          field: I18n.t('bulkrax.importer.guided_import.stepper_response_formatter.row_errors_issue.row_label', row: error[:row], column: error[:column]),
          message: error[:message]
        }
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
