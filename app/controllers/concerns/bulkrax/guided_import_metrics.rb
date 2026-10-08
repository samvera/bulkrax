# frozen_string_literal: true

module Bulkrax
  module GuidedImportMetrics
    extend ActiveSupport::Concern

    private

    def metrics_session_id
      params[:metrics_session_id].to_s.first(64).presence
    end

    def guided_import_parser_fields
      fields = { 'guided_import' => true }
      fields['metrics_session_id'] = metrics_session_id if Bulkrax.config.guided_import_metrics_enabled && metrics_session_id
      fields
    end

    def record_validation_metric(result, duration_ms)
      return unless Bulkrax.config.guided_import_metrics_enabled

      ImportMetric.record(
        metric_type: 'validation',
        event: 'validation_complete',
        user_id: current_user&.id,
        session_id: metrics_session_id,
        outcome: validation_outcome(result),
        duration_ms: duration_ms,
        payload: validation_metric_payload(result)
      )
    rescue StandardError => e
      ImportMetric.log_failure(e)
    end

    def validation_outcome(result)
      return 'fail' unless result[:isValid]

      result[:hasWarnings] ? 'pass_with_warnings' : 'pass'
    end

    def validation_metric_payload(result)
      row_errors = Array(result[:rowErrors])
      {
        row_count: result[:rowCount].to_i,
        missing_required_count: Array(result[:missingRequired]).size,
        unrecognized_count: result[:unrecognized]&.size || 0,
        empty_columns_count: Array(result[:emptyColumns]).size,
        row_error_count: row_errors.count { |e| e[:severity] == 'error' },
        row_warning_count: row_errors.count { |e| e[:severity] == 'warning' },
        notice_count: Array(result[:notices]).size,
        has_zip: result[:zipIncluded].present?,
        missing_files_count: Array(result[:missingFiles]).size,
        error_types: validation_error_types(result, row_errors),
        warning_types: validation_warning_types(result, row_errors)
      }
    end

    def validation_error_types(result, row_errors)
      types = []
      types << 'missing_required_fields' if Array(result[:missingRequired]).any?
      types << 'missing_files'           if Array(result[:missingFiles]).any?
      types << 'row_errors'              if row_errors.any? { |e| e[:severity] == 'error' }
      types
    end

    def validation_warning_types(result, row_errors)
      types = []
      types << 'unrecognized_fields' if result[:unrecognized]&.any?
      types << 'empty_columns'       if Array(result[:emptyColumns]).any?
      types << 'row_warnings'        if row_errors.any? { |e| e[:severity] == 'warning' }
      types << 'notices'             if Array(result[:notices]).any?
      types
    end
  end
end
