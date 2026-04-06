# frozen_string_literal: true

module Bulkrax
  class MetricsAggregator
    attr_reader :from, :to

    def initialize(from: 30.days.ago, to: Time.current)
      @from = from
      @to   = to
    end

    def total_imports
      ImportMetric.import_outcomes.in_range(from, to).count
    end

    def first_attempt_success_rate
      outcomes = ImportMetric.import_outcomes.in_range(from, to)
                             .where("payload->>'is_first_attempt' = ?", 'true')
      total = outcomes.count
      return 0.0 if total.zero?
      successes = outcomes.where("payload->>'outcome' = ?", 'complete').count
      (successes.to_f / total * 100).round(1)
    end

    def avg_validation_duration_ms
      ImportMetric.validations.in_range(from, to)
                  .average("(payload->>'duration_ms')::integer")&.round(0).to_i
    end

    def validation_outcomes
      ImportMetric.validations.in_range(from, to)
                  .group("payload->>'outcome'")
                  .count
    end

    def funnel_data
      ImportMetric.funnel.in_range(from, to)
                  .group("(payload->>'step')::integer")
                  .count
    end

    def error_type_frequencies
      sql = <<-SQL
        SELECT elem AS error_type, COUNT(*) AS cnt
        FROM bulkrax_import_metrics,
             jsonb_array_elements_text(payload->'error_types') AS elem
        WHERE metric_type = 'validation'
          AND created_at BETWEEN ? AND ?
        GROUP BY elem
        ORDER BY cnt DESC
        LIMIT 10
      SQL
      ImportMetric.find_by_sql([sql, from, to])
    end

    def avg_seq_rating
      ImportMetric.feedback.in_range(from, to)
                  .average("(payload->>'seq_rating')::integer")&.round(1).to_f
    end

    def seq_distribution
      ImportMetric.feedback.in_range(from, to)
                  .group("(payload->>'seq_rating')::integer")
                  .count
    end

    def seq_response_count
      ImportMetric.feedback.in_range(from, to).count
    end

    def recent_comments(limit: 20)
      ImportMetric.feedback.in_range(from, to)
                  .where("payload->>'comment' IS NOT NULL")
                  .where("payload->>'comment' != ''")
                  .order(created_at: :desc)
                  .limit(limit)
                  .pluck(:payload, :created_at)
                  .map { |p, t| { rating: p['seq_rating'], comment: p['comment'], date: t } }
    end

    def imports_over_time
      ImportMetric.import_outcomes.in_range(from, to)
                  .group("date_trunc('day', created_at)")
                  .group("payload->>'outcome'")
                  .count
    end

    def recent_imports(limit: 50)
      ImportMetric.import_outcomes.in_range(from, to)
                  .order(created_at: :desc)
                  .limit(limit)
                  .includes(:importer, :user)
    end

    def export_rows
      ImportMetric.in_range(from, to).order(:created_at).map do |m|
        {
          id:          m.id,
          metric_type: m.metric_type,
          event:       m.event,
          importer_id: m.importer_id,
          user_id:     m.user_id,
          session_id:  m.session_id,
          created_at:  m.created_at.iso8601,
          payload:     m.payload.to_json
        }
      end
    end
  end
end
