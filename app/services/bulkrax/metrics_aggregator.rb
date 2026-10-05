# frozen_string_literal: true

module Bulkrax
  # Summaries for the guided import metrics dashboard. Every figure reads the
  # outcome recorded when a run finished, never an importer's current status,
  # so later re-runs cannot rewrite history.
  class MetricsAggregator
    STEPS = (1..4).freeze
    RATINGS = (1..7).freeze

    attr_reader :from, :to

    def initialize(from:, to:)
      @from = from
      @to = to
    end

    def total_imports
      outcomes.count
    end

    def first_attempt_success_rate
      first_runs = outcomes.where(first_attempt: true)
      total = first_runs.count
      return if total.zero?

      (first_runs.where(outcome: 'Complete').count * 100.0 / total).round(1)
    end

    def average_validation_ms
      in_range(ImportMetric.validations).average(:duration_ms)&.round
    end

    def funnel
      counts = in_range(ImportMetric.where(metric_type: 'funnel')).where.not(session_id: nil).group(:step).distinct.count(:session_id)
      STEPS.index_with { |step| counts.fetch(step, 0) }
    end

    def error_type_frequencies(limit: 10)
      in_range(ImportMetric.validations).pluck(:payload)
                                        .flat_map { |payload| Array(payload&.dig('error_types')) }
                                        .tally
                                        .sort_by { |type, count| [-count, type] }
                                        .first(limit)
    end

    # How each first run turned out, grouped by the last validation result in
    # the same wizard session ('not_validated' when the session has none).
    def validation_accuracy
      runs = outcomes.where(first_attempt: true).pluck(:session_id, :outcome)
      last_validation = ImportMetric.validations.where(session_id: runs.map(&:first).compact).order(:created_at).pluck(:session_id, :outcome).to_h

      runs.each_with_object(Hash.new { |h, k| h[k] = Hash.new(0) }) do |(session_id, outcome), table|
        table[last_validation.fetch(session_id, 'not_validated')][outcome] += 1
      end
    end

    def average_rating
      feedback.average(:rating)&.to_f&.round(1)
    end

    def rating_distribution
      counts = feedback.group(:rating).count
      RATINGS.index_with { |rating| counts.fetch(rating, 0) }
    end

    def response_count
      feedback.count
    end

    # Matches the raw JSON the metrics endpoint writes for a rating sent
    # without a comment, so the limit applies only to rows with one.
    def recent_comments(limit: 20)
      feedback.where('payload IS NOT NULL AND payload NOT IN (?)', ['{}', '{"comment":""}'])
              .order(created_at: :desc).limit(limit)
              .map { |m| { rating: m.rating, comment: m.payload['comment'], date: m.created_at } }
    end

    def imports_by_day
      outcomes.order(created_at: :desc).pluck(:created_at, :outcome).each_with_object({}) do |(created_at, outcome), days|
        day = days[created_at.to_date] ||= { complete: 0, other: 0 }
        day[outcome == 'Complete' ? :complete : :other] += 1
      end
    end

    def recent_imports(limit: 50)
      outcomes.order(created_at: :desc).limit(limit).includes(:importer)
    end

    def each_export_row
      return enum_for(:each_export_row) unless block_given?

      in_range(ImportMetric.all).find_each do |m|
        yield [m.id, m.metric_type, m.event, m.importer_id, m.importer_run_id, m.user_id, m.session_id, m.outcome,
               m.first_attempt, m.duration_ms, m.step, m.rating, m.created_at.iso8601, m.payload.to_json]
      end
    end

    private

    def outcomes
      in_range(ImportMetric.import_outcomes)
    end

    def feedback
      in_range(ImportMetric.where(metric_type: 'feedback'))
    end

    def in_range(scope)
      scope.in_range(from, to)
    end
  end
end
