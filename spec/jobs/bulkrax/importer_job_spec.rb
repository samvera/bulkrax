# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ImporterJob, type: :job do
    subject(:importer_job) { described_class.new }
    let(:importer) { FactoryBot.create(:bulkrax_importer_oai) }

    before do
      allow(Bulkrax::Importer).to receive(:find).with(1).and_return(importer)
    end

    describe 'successful job' do
      it 'calls import_works with false' do
        expect(importer).to receive(:import_works)
        importer_job.perform(1)
      end

      it 'calls import_works with true if only_updates_since_last_import=true' do
        expect(importer).to receive(:import_works)
        importer_job.perform(1, true)
      end

      it 'updates the current run counters' do
        expect(importer).to receive(:import_works)
        importer_job.perform(1)

        expect(importer.current_run.total_work_entries).to eq(10)
        expect(importer.current_run.total_collection_entries).to eq(421)
      end
    end

    describe 'failed job' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv_bad) }

      it 'returns for an invalid import' do
        expect(importer).not_to receive(:import_collections)
        expect(importer).not_to receive(:import_works)
      end
    end

    describe 'schedulable' do
      before do
        allow(importer).to receive(:schedulable?).and_return(true)
        allow(importer).to receive(:next_import_at).and_return(1)
      end

      it 'schedules import_works when schedulable?' do
        expect(importer).to receive(:import_works)
        expect(described_class).to receive(:set).with(wait_until: 1).and_return(described_class)
        importer_job.perform(1)
      end
    end
  end
end
