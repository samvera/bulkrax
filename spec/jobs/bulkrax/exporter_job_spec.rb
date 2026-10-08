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
          expect(exporter).to receive(:save).at_least(:once).and_call_original

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

      context 'when the export matched no records' do
        it 'marks the exporter Complete instead of leaving it Pending' do
          allow(exporter).to receive(:export)

          described_class.perform_now(exporter.id)

          expect(exporter.status).to eq('Complete')
        end
      end

      context 'when an entry failed without the run getting a status' do
        it 'marks the exporter Complete (with failures)' do
          allow(exporter).to receive(:export) { bulkrax_exporter_run.update!(failed_records: 1) }

          described_class.perform_now(exporter.id)

          expect(exporter.status).to eq('Complete (with failures)')
        end
      end

      context 'when writing the files fails' do
        it 'marks the exporter Failed with the error, even after its entries completed' do
          allow(exporter).to receive(:export) { exporter.set_status_info }
          allow(exporter).to receive(:write).and_raise(StandardError, 'Unable to retrieve files')

          expect { described_class.perform_now(exporter.id) }.to raise_error(StandardError, 'Unable to retrieve files')
          expect(exporter.status).to eq('Failed')
          expect(exporter.current_status.error_message).to eq('Unable to retrieve files')
        end
      end

      context 'when the export itself failed' do
        it 'keeps the Failed status' do
          allow(exporter).to receive(:export) { exporter.set_status_info(StandardError.new('Solr said no')) }

          described_class.perform_now(exporter.id)

          expect(exporter.status).to eq('Failed')
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
