# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe MetricsAggregator, type: :model do
    let(:from) { 7.days.ago }
    let(:to) { Time.current }
    let(:aggregator) { described_class.new(from: from, to: to) }

    def create_metric(attrs = {})
      ImportMetric.record(**{ metric_type: 'funnel', event: 'test' }.merge(attrs))
    end

    describe '#total_imports' do
      it 'returns 0 with no data' do
        expect(aggregator.total_imports).to eq(0)
      end

      it 'counts only import_outcome metrics' do
        create_metric(metric_type: 'import_outcome', event: 'import_complete', payload: { outcome: 'complete' })
        create_metric(metric_type: 'import_outcome', event: 'import_complete', payload: { outcome: 'failed' })
        create_metric(metric_type: 'validation', event: 'validation_complete')
        expect(aggregator.total_imports).to eq(2)
      end
    end

    describe '#first_attempt_success_rate' do
      it 'returns 0.0 with no data' do
        stub_postgres_scope(:import_outcomes, 0)
        expect(aggregator.first_attempt_success_rate).to eq(0.0)
      end

      it 'returns correct percentage with mixed outcomes' do
        create_metric(metric_type: 'import_outcome', event: 'import_complete',
                      payload: { outcome: 'complete', is_first_attempt: true })
        create_metric(metric_type: 'import_outcome', event: 'import_complete',
                      payload: { outcome: 'complete', is_first_attempt: true })
        create_metric(metric_type: 'import_outcome', event: 'import_complete',
                      payload: { outcome: 'failed', is_first_attempt: true })

        unless DatabaseHelpers.postgres?
          relation = double('ImportMetric::Relation') # rubocop:disable RSpec/VerifiedDoubles
          allow(ImportMetric).to receive(:import_outcomes).and_return(relation)
          allow(relation).to receive(:in_range).and_return(relation)
          allow(relation).to receive(:where).and_return(relation)
          allow(relation).to receive(:count).and_return(3, 2)
        end

        expect(aggregator.first_attempt_success_rate).to eq(66.7)
      end

      it 'only counts first attempts' do
        create_metric(metric_type: 'import_outcome', event: 'import_complete',
                      payload: { outcome: 'complete', is_first_attempt: true })
        create_metric(metric_type: 'import_outcome', event: 'import_complete',
                      payload: { outcome: 'failed', is_first_attempt: false })

        unless DatabaseHelpers.postgres?
          relation = double('ImportMetric::Relation') # rubocop:disable RSpec/VerifiedDoubles
          allow(ImportMetric).to receive(:import_outcomes).and_return(relation)
          allow(relation).to receive(:in_range).and_return(relation)
          allow(relation).to receive(:where).and_return(relation)
          allow(relation).to receive(:count).and_return(1, 1)
        end

        expect(aggregator.first_attempt_success_rate).to eq(100.0)
      end
    end

    describe '#avg_validation_duration_ms' do
      it 'returns 0 with no data' do
        stub_postgres_scope(:validations, nil)
        expect(aggregator.avg_validation_duration_ms).to eq(0)
      end

      it 'returns the average duration rounded to integer' do
        create_metric(metric_type: 'validation', event: 'validation_complete', payload: { duration_ms: 1000 })
        create_metric(metric_type: 'validation', event: 'validation_complete', payload: { duration_ms: 2000 })
        stub_postgres_scope(:validations, BigDecimal('1500.4'))
        expect(aggregator.avg_validation_duration_ms).to eq(1500)
      end
    end

    describe '#validation_outcomes' do
      it 'returns empty hash with no data' do
        stub_postgres_scope(:validations, {})
        expect(aggregator.validation_outcomes).to eq({})
      end

      it 'groups by outcome' do
        create_metric(metric_type: 'validation', event: 'validation_complete', payload: { outcome: 'pass' })
        create_metric(metric_type: 'validation', event: 'validation_complete', payload: { outcome: 'pass' })
        create_metric(metric_type: 'validation', event: 'validation_complete', payload: { outcome: 'fail' })
        stub_postgres_scope(:validations, { 'pass' => 2, 'fail' => 1 })
        result = aggregator.validation_outcomes
        expect(result['pass']).to eq(2)
        expect(result['fail']).to eq(1)
      end
    end

    describe '#funnel_data' do
      it 'returns empty hash with no data' do
        stub_postgres_scope(:funnel, {})
        expect(aggregator.funnel_data).to eq({})
      end

      it 'groups by step number' do
        create_metric(metric_type: 'funnel', event: 'step_reached', payload: { step: 1 })
        create_metric(metric_type: 'funnel', event: 'step_reached', payload: { step: 1 })
        create_metric(metric_type: 'funnel', event: 'step_reached', payload: { step: 2 })
        stub_postgres_scope(:funnel, { 1 => 2, 2 => 1 })
        result = aggregator.funnel_data
        expect(result[1]).to eq(2)
        expect(result[2]).to eq(1)
      end
    end

    describe '#error_type_frequencies' do
      it 'returns empty array with no data' do
        stub_postgres_find_by_sql([])
        expect(aggregator.error_type_frequencies).to eq([])
      end

      it 'unnests JSONB arrays and counts by type' do
        create_metric(metric_type: 'validation', event: 'validation_complete',
                      payload: { error_types: %w[missing_required_fields row_errors] })
        create_metric(metric_type: 'validation', event: 'validation_complete',
                      payload: { error_types: ['missing_required_fields'] })

        row1 = ImportMetric.new
        row1.define_singleton_method(:error_type) { 'missing_required_fields' }
        row1.define_singleton_method(:cnt) { 2 }
        row2 = ImportMetric.new
        row2.define_singleton_method(:error_type) { 'row_errors' }
        row2.define_singleton_method(:cnt) { 1 }
        stub_postgres_find_by_sql([row1, row2])

        results = aggregator.error_type_frequencies
        types = results.map { |r| [r.error_type, r.cnt.to_i] }.to_h
        expect(types['missing_required_fields']).to eq(2)
        expect(types['row_errors']).to eq(1)
      end
    end

    describe '#avg_seq_rating' do
      it 'returns 0.0 with no data' do
        stub_postgres_scope(:feedback, nil)
        expect(aggregator.avg_seq_rating).to eq(0.0)
      end

      it 'returns the average rating rounded to 1 decimal' do
        create_metric(metric_type: 'feedback', event: 'seq_rating', payload: { seq_rating: 5 })
        create_metric(metric_type: 'feedback', event: 'seq_rating', payload: { seq_rating: 7 })
        stub_postgres_scope(:feedback, BigDecimal('6.0'))
        expect(aggregator.avg_seq_rating).to eq(6.0)
      end
    end

    describe '#seq_distribution' do
      it 'returns empty hash with no data' do
        stub_postgres_scope(:feedback, {})
        expect(aggregator.seq_distribution).to eq({})
      end

      it 'groups by rating value' do
        create_metric(metric_type: 'feedback', event: 'seq_rating', payload: { seq_rating: 5 })
        create_metric(metric_type: 'feedback', event: 'seq_rating', payload: { seq_rating: 5 })
        create_metric(metric_type: 'feedback', event: 'seq_rating', payload: { seq_rating: 7 })
        stub_postgres_scope(:feedback, { 5 => 2, 7 => 1 })
        result = aggregator.seq_distribution
        expect(result[5]).to eq(2)
        expect(result[7]).to eq(1)
      end
    end

    describe '#seq_response_count' do
      it 'returns 0 with no data' do
        expect(aggregator.seq_response_count).to eq(0)
      end

      it 'counts only feedback metrics' do
        create_metric(metric_type: 'feedback', event: 'seq_rating', payload: { seq_rating: 5 })
        create_metric(metric_type: 'funnel', event: 'step_reached')
        expect(aggregator.seq_response_count).to eq(1)
      end
    end

    describe '#recent_comments' do
      it 'returns empty array with no data' do
        stub_postgres_scope(:feedback, [])
        expect(aggregator.recent_comments).to eq([])
      end

      it 'returns comments with rating and date' do
        now = Time.current
        create_metric(metric_type: 'feedback', event: 'seq_rating',
                      payload: { seq_rating: 6, comment: 'Great tool!' })
        stub_postgres_scope(:feedback, [[{ 'seq_rating' => 6, 'comment' => 'Great tool!' }, now]])
        results = aggregator.recent_comments
        expect(results.size).to eq(1)
        expect(results.first[:rating]).to eq(6)
        expect(results.first[:comment]).to eq('Great tool!')
        expect(results.first[:date]).to eq(now)
      end

      it 'excludes blank comments' do
        create_metric(metric_type: 'feedback', event: 'seq_rating',
                      payload: { seq_rating: 5, comment: '' })
        create_metric(metric_type: 'feedback', event: 'seq_rating',
                      payload: { seq_rating: 6, comment: 'Useful' })
        stub_postgres_scope(:feedback, [[{ 'seq_rating' => 6, 'comment' => 'Useful' }, Time.current]])
        expect(aggregator.recent_comments.size).to eq(1)
      end

      it 'respects the limit parameter' do
        3.times { |i| create_metric(metric_type: 'feedback', event: 'seq_rating', payload: { seq_rating: i + 5, comment: "Comment #{i}" }) }
        comments = Array.new(2) { |i| [{ 'seq_rating' => i + 5, 'comment' => "Comment #{i}" }, Time.current] }
        relation = stub_postgres_scope(:feedback, comments)
        if relation
          allow(relation).to receive(:limit).with(2).and_return(relation)
          allow(relation).to receive(:pluck).and_return(comments)
        end
        expect(aggregator.recent_comments(limit: 2).size).to eq(2)
      end
    end

    describe '#imports_over_time' do
      it 'returns empty hash with no data' do
        stub_postgres_scope(:import_outcomes, {})
        expect(aggregator.imports_over_time).to eq({})
      end

      it 'groups by day and outcome' do
        create_metric(metric_type: 'import_outcome', event: 'import_complete', payload: { outcome: 'complete' })
        create_metric(metric_type: 'import_outcome', event: 'import_complete', payload: { outcome: 'failed' })
        today = Time.current.beginning_of_day
        stub_postgres_scope(:import_outcomes, { [today, 'complete'] => 1, [today, 'failed'] => 1 })
        result = aggregator.imports_over_time
        expect(result.values.sum).to eq(2)
      end
    end

    describe '#recent_imports' do
      it 'returns empty relation with no data' do
        expect(aggregator.recent_imports).to be_empty
      end

      it 'returns import_outcome metrics ordered by most recent' do
        create_metric(metric_type: 'import_outcome', event: 'import_complete', payload: { outcome: 'complete' })
        m2 = create_metric(metric_type: 'import_outcome', event: 'import_complete', payload: { outcome: 'failed' })
        results = aggregator.recent_imports
        expect(results.first.id).to eq(m2.id)
      end

      it 'respects the limit parameter' do
        3.times { create_metric(metric_type: 'import_outcome', event: 'import_complete', payload: { outcome: 'complete' }) }
        expect(aggregator.recent_imports(limit: 2).size).to eq(2)
      end
    end

    describe '#validation_to_outcome_correlation' do
      it 'returns empty array with no data' do
        stub_postgres_find_by_sql([])
        expect(aggregator.validation_to_outcome_correlation).to eq([])
      end

      it 'joins validation and import_outcome metrics on session_id' do
        expect(ImportMetric).to receive(:find_by_sql) do |args|
          sql = args.first
          expect(sql).to include("v.session_id = o.session_id")
          expect(sql).to include("v.metric_type = 'validation'")
          expect(sql).to include("o.metric_type = 'import_outcome'")
          []
        end
        aggregator.validation_to_outcome_correlation
      end

      it 'passes the date range to the SQL query' do
        expect(ImportMetric).to receive(:find_by_sql) do |args|
          _sql, query_from, query_to = args
          expect(query_from).to be_within(1.second).of(from)
          expect(query_to).to be_within(1.second).of(to)
          []
        end
        aggregator.validation_to_outcome_correlation
      end

      it 'requires non-null session_id' do
        expect(ImportMetric).to receive(:find_by_sql) do |args|
          sql = args.first
          expect(sql).to include("v.session_id IS NOT NULL")
          []
        end
        aggregator.validation_to_outcome_correlation
      end
    end

    describe '#export_rows' do
      it 'returns empty array with no data' do
        expect(aggregator.export_rows).to eq([])
      end

      it 'returns all metrics in range with expected keys' do
        create_metric(metric_type: 'funnel', event: 'step_reached', session_id: 'gi_test', payload: { step: 1 })
        rows = aggregator.export_rows
        expect(rows.size).to eq(1)
        row = rows.first
        expect(row).to have_key(:id)
        expect(row).to have_key(:metric_type)
        expect(row).to have_key(:event)
        expect(row).to have_key(:importer_id)
        expect(row).to have_key(:user_id)
        expect(row).to have_key(:session_id)
        expect(row).to have_key(:created_at)
        expect(row).to have_key(:payload)
      end

      it 'serializes payload as JSON string' do
        create_metric(metric_type: 'funnel', event: 'step_reached', payload: { step: 1 })
        row = aggregator.export_rows.first
        expect(row[:payload]).to be_a(String)
        expect(JSON.parse(row[:payload])).to eq({ 'step' => 1 })
      end

      it 'orders by created_at' do
        m1 = create_metric(metric_type: 'funnel', event: 'first')
        m2 = create_metric(metric_type: 'funnel', event: 'second')
        rows = aggregator.export_rows
        expect(rows.first[:id]).to eq(m1.id)
        expect(rows.last[:id]).to eq(m2.id)
      end
    end
  end
end
