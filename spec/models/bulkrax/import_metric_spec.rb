# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ImportMetric, type: :model do
    describe 'validations' do
      it 'rejects an unknown metric_type' do
        metric = described_class.new(metric_type: 'invalid', event: 'test')
        expect(metric).not_to be_valid
        expect(metric.errors[:metric_type]).to be_present
      end

      it 'requires an event' do
        metric = described_class.new(metric_type: 'funnel')
        expect(metric).not_to be_valid
        expect(metric.errors[:event]).to be_present
      end

      described_class::METRIC_TYPES.each do |type|
        it "accepts the '#{type}' metric_type" do
          expect(described_class.new(metric_type: type, event: 'test')).to be_valid
        end
      end
    end

    describe '.record' do
      it 'round-trips the payload through the database' do
        metric = described_class.record(metric_type: 'funnel', event: 'step_reached', payload: { error_types: ['missing_files'] })
        expect(metric.reload.payload).to eq('error_types' => ['missing_files'])
      end

      it 'defaults the payload to an empty hash' do
        expect(described_class.record(metric_type: 'funnel', event: 'step_reached').reload.payload).to eq({})
      end

      it 'returns nil and logs instead of raising when the write fails' do
        allow(described_class).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'table missing')
        expect(Rails.logger).to receive(:warn).with(/Bulkrax::ImportMetric/)
        expect(described_class.record(metric_type: 'funnel', event: 'test')).to be_nil
      end
    end

    describe '.record_import_outcome' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }
      let(:run) { importer.current_run }

      it 'keeps one row per run, holding the latest outcome' do
        described_class.record_import_outcome(run, importer: importer, outcome: 'Complete (with failures)')
        described_class.record_import_outcome(run, importer: importer, outcome: 'Complete')

        metrics = described_class.import_outcomes.where(importer_run: run)
        expect(metrics.count).to eq(1)
        expect(metrics.first.outcome).to eq('Complete')
      end

      it 'leaves other metric types for the same run untouched' do
        feedback = described_class.record(metric_type: 'feedback', event: 'seq_rating', importer_run: run, rating: 6)
        described_class.record_import_outcome(run, importer: importer, outcome: 'Complete')

        expect(feedback.reload).to have_attributes(metric_type: 'feedback', rating: 6)
        expect(described_class.import_outcomes.where(importer_run: run).count).to eq(1)
      end

      it 'updates the existing row when another job inserted it first' do
        described_class.record_import_outcome(run, importer: importer, outcome: 'Complete (with failures)')
        stale_lookup = described_class.new(importer_run_id: run.id, metric_type: 'import_outcome')
        lookups = 0
        allow(described_class).to receive(:find_or_initialize_by).and_wrap_original do |original, *args, **kwargs|
          lookups += 1
          lookups == 1 ? stale_lookup : original.call(*args, **kwargs)
        end

        described_class.record_import_outcome(run, importer: importer, outcome: 'Complete')

        expect(described_class.import_outcomes.where(importer_run: run).pluck(:outcome)).to eq(['Complete'])
      end

      it 'returns nil and logs instead of raising when the write fails' do
        allow(described_class).to receive(:find_or_initialize_by).and_raise(ActiveRecord::StatementInvalid, 'table missing')
        expect(Rails.logger).to receive(:warn).with(/Bulkrax::ImportMetric/)
        expect(described_class.record_import_outcome(run, outcome: 'Complete')).to be_nil
      end
    end

    describe '.in_range' do
      it 'excludes metrics created outside the range' do
        old_metric = described_class.record(metric_type: 'funnel', event: 'test')
        old_metric.update!(created_at: 60.days.ago)
        recent_metric = described_class.record(metric_type: 'funnel', event: 'test')

        expect(described_class.in_range(7.days.ago, Time.current)).to contain_exactly(recent_metric)
      end
    end

    describe 'when the importer is destroyed' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }

      it 'keeps the metric with its importer and run links cleared' do
        metric = described_class.record_import_outcome(importer.current_run, importer: importer, outcome: 'Complete')
        importer.destroy!

        expect(metric.reload).to have_attributes(importer_id: nil, importer_run_id: nil, outcome: 'Complete')
      end
    end
  end
end
