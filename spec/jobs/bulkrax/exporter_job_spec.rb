# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ExporterJob, type: :job do
    subject(:exporter_job) { described_class.new }
    let(:exporter) { FactoryBot.create(:bulkrax_exporter) }
    let(:bulkrax_exporter_run) { FactoryBot.create(:bulkrax_exporter_run, exporter: exporter) }

    before do
      allow(Bulkrax::Exporter).to receive(:find).with(1).and_return(exporter)
      allow(exporter).to receive(:exporter_runs).and_return([bulkrax_exporter_run])
      allow(exporter).to receive(:mapping).and_return("title" => {})
      exporter.setup_export_path
      allow(exporter.parser).to receive(:write_files).and_return(exporter.exporter_export_path)
    end

    describe '#perform', clean_downloads: true do
      before do
        allow(Bulkrax::Exporter).to receive(:find).with(exporter.id).and_return(exporter)
      end

      context 'successful export' do
        it 'processes export successfully' do
          expect(exporter).to receive(:export)
          expect(exporter).to receive(:write)
          expect(exporter).to receive(:save)

          result = described_class.perform_now(exporter.id)
          expect(result).to be true
        end
      end

      context 'failed export' do
        it 'handles export failures gracefully' do
          allow(exporter).to receive(:export).and_raise(StandardError, 'Export failed')

          expect { described_class.perform_now(exporter.id) }.to raise_error(StandardError)
        end
      end

      context 'queue management' do
        it 'is queued on the export queue' do
          expect(described_class.queue_name).to eq('export')
        end
      end
    end

    describe '.perform_later' do
      it 'enqueues job for background processing' do
        expect { described_class.perform_later(exporter.id) }
          .to have_enqueued_job(described_class)
          .with(exporter.id)
          .on_queue('export')
      end
    end
  end
end
