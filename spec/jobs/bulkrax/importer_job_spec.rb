# frozen_string_literal: true

require 'rails_helper'
require 'libxml'

module Bulkrax
  RSpec.describe ImporterJob, type: :job do
    subject(:importer_job) { described_class.new(importer: importer) }
    let(:importer) { FactoryBot.create(:bulkrax_importer_oai) }
    let(:parser) { importer.parser }
    let(:doc) { LibXML::XML::Document.file('./spec/fixtures/oai/oai-pmh-ListSets.xml') }
    let(:response) { OAI::ListSetsResponse.new(doc) }
    let(:collections_count) { doc.to_s.scan(/<set>(.*?)<\/set>/m).count }

    before do
      allow(Bulkrax::Importer).to receive(:find).with(1).and_return(importer)
    end

    describe 'successful job' do
      it 'calls import_works with false' do
        expect(importer).to receive(:import_objects)
        importer_job.perform(importer.id)
      end

      it 'calls import_works with true if only_updates_since_last_import=true' do
        expect(importer).to receive(:import_objects)
        importer_job.perform(importer.id, true)
      end

      before do
        allow(parser).to receive(:collections).and_return(response)
        allow(parser.collections).to receive(:count).and_return(collections_count)
      end

      it 'updates the current run counters' do
        expect(importer).to receive(:import_objects)
        importer_job.perform(importer.id)

        expect(importer.current_run.total_work_entries).to eq(10)
        expect(importer.current_run.total_collection_entries).to eq(5)
      end
    end

    describe 'failed job' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv_bad) }

      it 'returns for an invalid import' do
        expect(importer).not_to receive(:import_objects)
      end

      context 'with malformed CSV' do
        let(:importer) { FactoryBot.create(:bulkrax_importer_csv_bad, parser_fields: { 'import_file_path' => 'spec/fixtures/csv/malformed.csv' }) }

        it 'logs the error on the importer' do
          importer_job.perform(importer.id)
          expect(importer.status).to eq('Failed')
        end

        it 'does not reschedule the job' do
          expect(importer_job).not_to receive(:schedule)

          importer_job.perform(importer.id)
        end
      end
    end

    describe 'schedulable' do
      before do
        allow(importer).to receive(:schedulable?).and_return(true)
        allow(importer).to receive(:next_import_at).and_return(1)
        allow(parser).to receive(:collections).and_return(response)
        allow(parser.collections).to receive(:count).and_return(collections_count)
      end

      it 'schedules import_works when schedulable?' do
        expect(importer).to receive(:import_objects)
        expect(described_class).to receive(:set).with(wait_until: 1).and_return(described_class)
        importer_job.perform(importer.id)
      end
    end
  end
end
