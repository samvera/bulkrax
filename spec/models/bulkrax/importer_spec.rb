require 'rails_helper'

module Bulkrax
  RSpec.describe Importer, type: :model do
    let(:importer) do
      FactoryBot.create(:bulkrax_importer, user: User.new(email: 'test@example.com'))
    end

    describe 'frequency' do
      it 'uses ISO 8601 for frequency' do
        importer.frequency = 'P1Y'
        expect(importer.frequency.to_seconds).to eq(31_536_000.0)
      end

      it 'uses ISO 8601 to determine schedulable' do
        importer.frequency = 'P1D'
        expect(importer.schedulable?).to eq(true)
      end
    end

    describe 'importer run' do
      it 'creates an ImporterRun with total_records set to the value of limit' do
        importer.current_importer_run
        expect(importer.current_importer_run.total_records).to eq(10)
      end
    end

    describe 'import works' do
      before do
        allow(Bulkrax::OaiDcParser).to receive(:new).and_return(Bulkrax::OaiDcParser.new(importer)) # .with(subject).and_return(parser)
        allow_any_instance_of(Bulkrax::OaiDcParser).to receive(:create_collections)
        allow_any_instance_of(Bulkrax::OaiDcParser).to receive(:create_works)
      end

      it 'calls parser run' do
        importer.import_works
        expect(importer.only_updates).to eq(false)
      end
    end
  end
end
