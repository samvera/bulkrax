# frozen_string_literal: true

module Bulkrax
  module GuidedImportMetrics
    extend ActiveSupport::Concern

    private

    def record_validation_metric(result, duration_ms)
      return unless Bulkrax.config.guided_import_metrics_enabled

      outcome = if result[:isValid]
                  result[:hasWarnings] ? 'pass_with_warnings' : 'pass'
                else
                  'fail'
                end

      Bulkrax::ImportMetric.record(
        metric_type: 'validation',
        event: 'validation_complete',
        user: current_user,
        session_id: params[:metrics_session_id],
        payload: validation_metric_payload(result, outcome, duration_ms)
      )
    end

    def validation_metric_payload(result, outcome, duration_ms)
      row_errors = Array(result[:rowErrors])
      {
        outcome: outcome,
        row_count: result[:rowCount].to_i,
        duration_ms: duration_ms,
        missing_required_count: Array(result[:missingRequired]).size,
        unrecognized_count: result[:unrecognized]&.size || 0,
        empty_columns_count: Array(result[:emptyColumns]).size,
        row_error_count: row_errors.count { |e| e[:severity] == 'error' },
        row_warning_count: row_errors.count { |e| e[:severity] == 'warning' },
        notice_count: Array(result[:notices]).size,
        has_zip: result[:zipIncluded].present?,
        missing_files_count: Array(result[:missingFiles]).size,
        error_types: extract_error_types(result),
        warning_types: extract_warning_types(result)
      }
    end

    def extract_error_types(result)
      types = []
      types << 'missing_required_fields' if Array(result[:missingRequired]).any?
      types << 'missing_files'           if Array(result[:missingFiles]).any?
      types << 'row_errors'              if Array(result[:rowErrors]).any? { |e| e[:severity] == 'error' }
      types
    end

    def extract_warning_types(result)
      types = []
      types << 'unrecognized_fields' if result[:unrecognized]&.any?
      types << 'empty_columns'       if Array(result[:emptyColumns]).any?
      types << 'row_warnings'        if Array(result[:rowErrors]).any? { |e| e[:severity] == 'warning' }
      types << 'notices'             if Array(result[:notices]).any?
      types
    end

    def cache_validation_errors(validation_result, raw_csv_data, csv_file)
      has_errors = validation_result[:rowErrors]&.any? ||
                   validation_result[:missingRequired]&.any? ||
                   validation_result[:unrecognized]&.any? ||
                   validation_result[:emptyColumns]&.any? ||
                   validation_result[:missingFiles]&.any?
      return nil unless has_errors

      key = "guided_import_errors:#{session.id}:#{Time.now.to_i}"
      Rails.cache.write(
        key,
        {
          headers: validation_result[:headers],
          csv_data: raw_csv_data,
          row_errors: validation_result[:rowErrors] || [],
          file_errors: {
            missing_required: validation_result[:missingRequired] || [],
            unrecognized: validation_result[:unrecognized] || {},
            empty_columns: validation_result[:emptyColumns] || [],
            missing_files: validation_result[:missingFiles] || []
          },
          original_filename: filename_for(csv_file)
        },
        expires_in: 1.hour
      )
      key
    end
  end
end
