# frozen_string_literal: true

module Bulkrax
  ##
  # Formats validation data from CsvParser.validate_csv into the structure
  # expected by the importers_stepper.js frontend component.
  #
  # This service acts as a presentation layer, transforming raw validation data
  # into a structured response with proper status messages, severity levels,
  # and formatted issue lists that the JavaScript can render correctly.
  #
  # @example Basic usage
  #   validation_data = CsvParser.validate_csv(csv_file: file, zip_file: zip)
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
    # @param data [Hash] Raw validation data from CsvParser.validate_csv containing:
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
      issues << notices_issue if @data[:notices]&.any?
      issues << unrecognized_fields_issue if @data[:unrecognized]&.any? || @data[:emptyColumns]&.any?
      issues << row_errors_issue if @data[:rowErrors]&.any? { |e| e[:severity] == 'error' }
      issues << row_warnings_issue if @data[:rowErrors]&.any? { |e| e[:severity] == 'warning' }

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
      recognized = @data[:headers].reject(&:blank?) - (@data[:unrecognized].keys || [])

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
      all_items = unrecognized_fields_issue_items
      {
        type: 'unrecognized_fields',
        severity: 'warning',
        icon: 'fa-exclamation-triangle',
        title: I18n.t('bulkrax.importer.guided_import.validation.unrecognized_title'),
        count: all_items.length,
        description: I18n.t('bulkrax.importer.guided_import.validation.unrecognized_desc'),
        items: all_items,
        defaultOpen: false
      }
    end

    def unrecognized_fields_issue_items
      named = (@data[:unrecognized] || {}).partition(&:last)
              .flatten(1)
              .map { |field| { field: field.first, message: field.last ? I18n.t('bulkrax.importer.guided_import.validation.did_you_mean', suggestion: field.last) : nil } }
      empty = (@data[:emptyColumns] || []).map do |col|
        { field: I18n.t('bulkrax.importer.guided_import.validation.empty_column', column: col), message: nil }
      end
      named + empty
    end

    def row_errors_issue
      entries = filtered_row_errors.select { |e| e[:severity] == 'error' }
      return nil if entries.empty?

      {
        type: 'row_level_errors',
        severity: 'error',
        icon: 'fa-times-circle',
        title: I18n.t('bulkrax.importer.guided_import.stepper_response_formatter.row_errors_issue.title_errors'),
        count: entries.length,
        description: I18n.t('bulkrax.importer.guided_import.stepper_response_formatter.row_errors_issue.description'),
        items: row_error_items(entries),
        defaultOpen: false
      }
    end

    def row_warnings_issue
      entries = filtered_row_errors.select { |e| e[:severity] == 'warning' }
      return nil if entries.empty?

      {
        type: 'row_level_warnings',
        severity: 'warning',
        icon: 'fa-exclamation-triangle',
        title: I18n.t('bulkrax.importer.guided_import.stepper_response_formatter.row_errors_issue.title_warnings'),
        count: entries.length,
        description: I18n.t('bulkrax.importer.guided_import.stepper_response_formatter.row_errors_issue.description'),
        items: row_error_items(entries),
        defaultOpen: false
      }
    end

    def notices_issue
      {
        type: 'notices',
        severity: 'warning',
        icon: 'fa-info-circle',
        title: I18n.t('bulkrax.importer.guided_import.validation.notices_title'),
        count: @data[:notices].length,
        description: I18n.t('bulkrax.importer.guided_import.validation.notices_desc'),
        items: @data[:notices].map { |n| { field: n[:field], message: [n[:message], n[:suggestion]].compact.join(' ') } },
        defaultOpen: false
      }
    end

    def filtered_row_errors
      missing_required_columns = @data[:missingRequired]&.map { |h| h[:field].to_s } || []
      notice_columns = @data[:notices]&.map { |n| n[:field].to_s } || []
      suppressed_columns = (missing_required_columns + notice_columns).uniq
      @data[:rowErrors].reject { |e| suppressed_columns.include?(e[:column].to_s) }
    end

    def row_error_items(errors)
      errors.map do |error|
        message = error[:message]
        message = [message, error[:suggestion]].compact.join(' ') if error[:suggestion].present?
        {
          field: I18n.t('bulkrax.importer.guided_import.stepper_response_formatter.row_errors_issue.row_label', row: error[:row], column: error[:column]),
          message: message,
          category: error[:category]
        }
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
