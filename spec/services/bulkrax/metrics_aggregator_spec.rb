# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe MetricsAggregator do
    subject(:aggregator) { described_class.new(from: 7.days.ago, to: Time.current) }

    def outcome(status, first_attempt: true, session_id: nil, at: 1.day.ago)
      ImportMetric.record(metric_type: 'import_outcome', event: 'import_complete', outcome: status,
                          first_attempt: first_attempt, session_id: session_id, created_at: at)
    end

    def validation(result, session_id:, at: 2.days.ago, error_types: [])
      ImportMetric.record(metric_type: 'validation', event: 'validation_complete', outcome: result, session_id: session_id,
                          duration_ms: 1_000, created_at: at, payload: { error_types: error_types })
    end

    def funnel(step, session_id)
      ImportMetric.record(metric_type: 'funnel', event: 'step_reached', step: step, session_id: session_id, created_at: 1.day.ago)
    end

    def feedback(rating, comment: '')
      ImportMetric.record(metric_type: 'feedback', event: 'seq_rating', rating: rating, created_at: 1.day.ago, payload: { comment: comment })
    end

    describe '#first_attempt_success_rate' do
      it 'uses the status each first run finished with, ignoring re-runs' do
        outcome('Complete')
        outcome('Failed')
        outcome('Complete', first_attempt: false)

        expect(aggregator.first_attempt_success_rate).to eq(50.0)
      end

      it 'is nil when no first runs finished in the range' do
        outcome('Complete', at: 30.days.ago)
        expect(aggregator.first_attempt_success_rate).to be_nil
      end
    end

    describe '#validation_accuracy' do
      it 'pairs each first run with the last validation in its session' do
        validation('fail', session_id: 'a', at: 3.days.ago)
        validation('pass', session_id: 'a', at: 2.days.ago)
        outcome('Complete', session_id: 'a')
        validation('pass_with_warnings', session_id: 'b')
        outcome('Failed', session_id: 'b')
        outcome('Complete', session_id: 'c')
        outcome('Failed', session_id: 'a', first_attempt: false)
        outcome('Failed')

        expect(aggregator.validation_accuracy).to eq(
          'pass' => { 'Complete' => 1 },
          'pass_with_warnings' => { 'Failed' => 1 },
          'not_validated' => { 'Complete' => 1, 'Failed' => 1 }
        )
      end
    end

    describe '#funnel' do
      it 'counts each session once per step' do
        funnel(1, 'a')
        funnel(2, 'a')
        funnel(2, 'a')
        funnel(1, 'b')

        expect(aggregator.funnel).to eq(1 => 2, 2 => 1, 3 => 0, 4 => 0)
      end
    end

    describe '#error_type_frequencies' do
      it 'counts how many validations reported each kind of error, most frequent first' do
        validation('fail', session_id: 'a', error_types: %w[missing_files row_errors])
        validation('fail', session_id: 'b', error_types: %w[row_errors])

        expect(aggregator.error_type_frequencies).to eq([['row_errors', 2], ['missing_files', 1]])
      end
    end

    describe 'feedback' do
      before do
        feedback(7, comment: 'Easy')
        feedback(4)
        feedback(4, comment: 'Confusing step 2')
      end

      it 'averages the ratings' do
        expect(aggregator.average_rating).to eq(5.0)
      end

      it 'counts responses for every point on the scale' do
        expect(aggregator.rating_distribution).to eq(1 => 0, 2 => 0, 3 => 0, 4 => 2, 5 => 0, 6 => 0, 7 => 1)
      end

      it 'lists only responses with a comment, newest first' do
        expect(aggregator.recent_comments.map { |c| c[:comment] }).to eq(['Confusing step 2', 'Easy'])
      end

      it 'still finds comments behind many newer ratings without one' do
        ImportMetric.where(metric_type: 'feedback').update_all(created_at: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations
        120.times { feedback(5) }
        expect(aggregator.recent_comments(limit: 2).size).to eq(2)
      end
    end

    describe '#imports_by_day' do
      it 'splits each day into completed and other outcomes' do
        outcome('Complete', at: 1.day.ago)
        outcome('Complete (with failures)', at: 1.day.ago)
        outcome('Complete', at: 2.days.ago)

        expect(aggregator.imports_by_day).to eq(
          1.day.ago.to_date => { complete: 1, other: 1 },
          2.days.ago.to_date => { complete: 1, other: 0 }
        )
      end
    end

    describe '#average_validation_ms' do
      it 'is nil when nothing was validated in the range' do
        expect(aggregator.average_validation_ms).to be_nil
      end
    end
  end
end
