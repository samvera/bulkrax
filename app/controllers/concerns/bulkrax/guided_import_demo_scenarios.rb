# frozen_string_literal: true

module Bulkrax
  # rubocop:disable Metrics/ModuleLength
  module GuidedImportDemoScenarios
    extend ActiveSupport::Concern

    # Serve demo scenario fixtures for frontend testing
    def demo_scenarios
      file_path = Bulkrax::Engine.root.join('lib', 'bulkrax', 'data', 'demo_scenarios.json')
      if File.exist?(file_path)
        render json: File.read(file_path), status: :ok
      else
        render json: { error: I18n.t('bulkrax.importer.guided_import.flash.demo_not_available') }, status: :not_found
      end
    end

    private

    def run_validation(csv_file, zip_file, admin_set_id: nil)
      if ENV['DEMO_MODE'] == 'true'
        generate_validation_response(csv_file, zip_file)
      else
        super
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
      zip_included = zip_file.present?
      missing_file_paths = ['photo_087.tiff', 'letter_scan_12.pdf', 'recording_03.wav']
      row_warnings = if zip_included
                       missing_file_paths.each_with_index.map do |path, i|
                         {
                           row: 10 + (i * 15),
                           severity: 'warning',
                           category: 'missing_file_reference',
                           column: 'file',
                           value: path,
                           message: I18n.t('bulkrax.importer.guided_import.validation.file_reference_validator.errors.missing_file_reference.message', value: path),
                           suggestion: I18n.t('bulkrax.importer.guided_import.validation.file_reference_validator.errors.missing_file_reference.suggestion')
                         }
                       end
                     else
                       []
                     end
      notices = if zip_included
                  []
                else
                  [{
                    field: 'file',
                    category: 'files_referenced_no_zip',
                    message: I18n.t('bulkrax.importer.guided_import.validation.files_referenced_no_zip_notice.message'),
                    suggestion: I18n.t('bulkrax.importer.guided_import.validation.files_referenced_no_zip_notice.suggestion')
                  }]
                end

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
        rowErrors: row_warnings,
        notices: notices,
        messages: build_validation_messages(
          headers: headers, unrecognized: unrecognized, missing_required: missing_required,
          row_warnings: row_warnings, notices: notices, row_count: 247,
          is_valid: true, has_warnings: true
        )
      }
    end
    # rubocop:enable Metrics/MethodLength

    # Builds the structured messages hash from validation results.
    # @param results [Hash] with keys: headers, unrecognized, missing_required,
    #   row_warnings, notices, row_count, is_valid, has_warnings
    def build_validation_messages(results)
      issues = []
      issues << missing_required_issue(results[:missing_required]) if results[:missing_required]&.any?
      issues << notices_issue(results[:notices]) if results[:notices]&.any?
      issues << unrecognized_fields_issue(results[:unrecognized]) if results[:unrecognized]&.any?
      issues << row_level_warnings_issue(results[:row_warnings]) if results[:row_warnings]&.any?

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

    def notices_issue(notices)
      {
        type: 'notices',
        severity: 'warning',
        icon: 'fa-info-circle',
        title: I18n.t('bulkrax.importer.guided_import.validation.notices_title'),
        count: notices.length,
        description: I18n.t('bulkrax.importer.guided_import.validation.notices_desc'),
        items: notices.map { |n| { field: n[:field], message: [n[:message], n[:suggestion]].compact.join(' ') } },
        defaultOpen: false
      }
    end

    def row_level_warnings_issue(row_warnings)
      {
        type: 'row_level_warnings',
        severity: 'warning',
        icon: 'fa-exclamation-triangle',
        title: I18n.t('bulkrax.importer.guided_import.stepper_response_formatter.row_errors_issue.title_warnings'),
        count: row_warnings.length,
        description: I18n.t('bulkrax.importer.guided_import.stepper_response_formatter.row_errors_issue.description'),
        items: row_warnings.map do |error|
          {
            field: I18n.t('bulkrax.importer.guided_import.stepper_response_formatter.row_errors_issue.row_label', row: error[:row], column: error[:column]),
            message: [error[:message], error[:suggestion]].compact.join(' '),
            category: error[:category]
          }
        end,
        defaultOpen: false
      }
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
