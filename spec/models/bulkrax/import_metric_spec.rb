# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ImportMetric, type: :model do
    describe 'validations' do
      it 'requires metric_type' do
        metric = described_class.new(event: 'test')
        expect(metric).not_to be_valid
        expect(metric.errors[:metric_type]).to include("can't be blank")
      end

      it 'requires event' do
        metric = described_class.new(metric_type: 'funnel')
        expect(metric).not_to be_valid
        expect(metric.errors[:event]).to include("can't be blank")
      end

      it 'validates metric_type inclusion' do
        metric = described_class.new(metric_type: 'invalid', event: 'test')
        expect(metric).not_to be_valid
        expect(metric.errors[:metric_type]).to include('is not included in the list')
      end

      %w[funnel validation import_outcome feedback timing].each do |type|
        it "accepts metric_type '#{type}'" do
          metric = described_class.new(metric_type: type, event: 'test')
          expect(metric).to be_valid
        end
      end
    end

    describe 'associations' do
      it 'belongs to importer optionally' do
        metric = described_class.new(metric_type: 'funnel', event: 'test')
        expect(metric).to be_valid
      end

      it 'belongs to user optionally' do
        metric = described_class.new(metric_type: 'funnel', event: 'test')
        expect(metric).to be_valid
      end
    end

    describe '.record' do
      it 'creates a metric with valid attributes' do
        metric = described_class.record(metric_type: 'funnel', event: 'step_reached', payload: { step: 1 })
        expect(metric).to be_persisted
        expect(metric.metric_type).to eq('funnel')
        expect(metric.event).to eq('step_reached')
        expect(metric.payload).to eq({ 'step' => 1 })
      end

      it 'sets payload to empty hash when not provided' do
        metric = described_class.record(metric_type: 'funnel', event: 'step_reached')
        expect(metric.payload).to eq({})
      end

      it 'stores session_id' do
        metric = described_class.record(metric_type: 'funnel', event: 'step_reached', session_id: 'gi_abc123')
        expect(metric.session_id).to eq('gi_abc123')
      end

      it 'never raises on failure' do
        allow(described_class).to receive(:create).and_raise(ActiveRecord::StatementInvalid, 'table missing')
        expect { described_class.record(metric_type: 'funnel', event: 'test') }.not_to raise_error
      end

      it 'returns nil on failure' do
        allow(described_class).to receive(:create).and_raise(ActiveRecord::StatementInvalid, 'table missing')
        expect(described_class.record(metric_type: 'funnel', event: 'test')).to be_nil
      end

      it 'logs a warning on failure' do
        allow(described_class).to receive(:create).and_raise(ActiveRecord::StatementInvalid, 'table missing')
        expect(Rails.logger).to receive(:warn).with(/Bulkrax::ImportMetric\.record failed/)
        described_class.record(metric_type: 'funnel', event: 'test')
      end
    end

    describe 'scopes' do
      before do
        described_class.record(metric_type: 'funnel', event: 'step_reached')
        described_class.record(metric_type: 'validation', event: 'validation_complete')
        described_class.record(metric_type: 'import_outcome', event: 'import_complete')
        described_class.record(metric_type: 'feedback', event: 'seq_rating')
        described_class.record(metric_type: 'timing', event: 'session_complete')
      end

      it '.funnel returns only funnel metrics' do
        expect(described_class.funnel.pluck(:metric_type).uniq).to eq(['funnel'])
      end

      it '.validations returns only validation metrics' do
        expect(described_class.validations.pluck(:metric_type).uniq).to eq(['validation'])
      end

      it '.import_outcomes returns only import_outcome metrics' do
        expect(described_class.import_outcomes.pluck(:metric_type).uniq).to eq(['import_outcome'])
      end

      it '.feedback returns only feedback metrics' do
        expect(described_class.feedback.pluck(:metric_type).uniq).to eq(['feedback'])
      end

      it '.timing returns only timing metrics' do
        expect(described_class.timing.pluck(:metric_type).uniq).to eq(['timing'])
      end
    end

    describe '.in_range' do
      it 'filters by date range' do
        old_metric = described_class.record(metric_type: 'funnel', event: 'test')
        old_metric.update(created_at: 60.days.ago)

        recent_metric = described_class.record(metric_type: 'funnel', event: 'test')

        results = described_class.in_range(7.days.ago, Time.current)
        expect(results).to include(recent_metric)
        expect(results).not_to include(old_metric)
      end
    end
  end
end
