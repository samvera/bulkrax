# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe MetricsAggregator, type: :model do
    let(:from) { 7.days.ago }
    let(:to) { Time.current }
    let(:aggregator) { described_class.new(from: from, to: to) }

    describe '#validation_to_outcome_correlation' do
      let(:correlated_row) do
        row = ImportMetric.new
        row.define_singleton_method(:validation_outcome) { 'pass' }
        row.define_singleton_method(:import_outcome) { 'complete' }
        row.define_singleton_method(:cnt) { 1 }
        row
      end

      it 'returns correlated validation and import outcomes' do
        expect(ImportMetric).to receive(:find_by_sql).and_return([correlated_row])
        results = aggregator.validation_to_outcome_correlation
        expect(results.size).to eq(1)
        expect(results.first.validation_outcome).to eq('pass')
        expect(results.first.import_outcome).to eq('complete')
        expect(results.first.cnt).to eq(1)
      end

      it 'passes the date range to the SQL query' do
        expect(ImportMetric).to receive(:find_by_sql) do |args|
          sql, query_from, query_to = args
          expect(sql).to include('bulkrax_import_metrics v')
          expect(sql).to include("v.session_id IS NOT NULL")
          expect(query_from).to be_within(1.second).of(from)
          expect(query_to).to be_within(1.second).of(to)
          []
        end
        aggregator.validation_to_outcome_correlation
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
    end
  end
end
