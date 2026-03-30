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
  end
  # rubocop:enable Metrics/ModuleLength
end
