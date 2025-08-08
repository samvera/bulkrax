# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ImportCollectionJob, type: :job do
    subject(:import_collection_job) { described_class.new(entry.id, current_run_id) }
    let(:entry) { FactoryBot.create(:bulkrax_csv_entry_collection) }
    let(:current_run_id) { entry.importerexporter.current_run.id }
    before do
      stub_request(:get, "http://commons.ptsem.edu/api/oai-pmh?verb=ListSets").to_return(status: 200, body: File.read('spec/fixtures/oai/oai-pmh-ListSets.xml'), headers: {})
    end
    it 'can be instantiated' do
      subject
    end

    describe '#perform' do
      subject(:perform) do
        import_collection_job.perform(
          entry.id, current_run_id
        )
      end
      context 'a successful run' do
        it 'increments the importer run count' do
          expect { perform }.to change(Bulkrax::ImporterRun, :count).by(1)
        end

        it 'increments the number of collections processed' do
          expect { perform }.to change { entry.importerexporter.current_run.reload.processed_collections }.by(1)
        end

        it 'does not decrement the number of enqueued records when it is already zero' do
          expect(entry.importerexporter.current_run.reload.enqueued_records).to eq(0)
          expect { perform }.not_to change { entry.importerexporter.current_run.reload.enqueued_records }
        end

        it 'decrements the number of enqueued records'
      end
      context 'a run with an error' do
        before do
          allow(Entry).to receive(:find).with(entry.id).and_return(entry)
          allow(entry).to receive(:build).and_raise(StandardError)
          allow(ImporterRun).to receive(:increment_counter).and_call_original
          allow(ImporterRun).to receive(:decrement_counter).and_call_original
        end

        it 'reraises the error' do
          expect { perform }.to raise_error(StandardError)
        end

        it 'increments the failed records and collections' do
          expect { perform }.to raise_error(StandardError)
          expect(ImporterRun).to have_received(:increment_counter).with(:failed_records, current_run_id).once
          expect(ImporterRun).to have_received(:increment_counter).with(:failed_collections, current_run_id).once
        end

        it 'does not decrement the number of enqueued records when it is already zero' do
          expect { perform }.to raise_error(StandardError)
          expect(ImporterRun).not_to have_received(:decrement_counter).with(:enqueued_records, current_run_id)
        end
        it 'decrements the number of enqueued records'
      end
    end
  end
end
