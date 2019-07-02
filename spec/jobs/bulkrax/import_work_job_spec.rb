require 'rails_helper'

module Bulkrax
  RSpec.describe ImportWorkJob, type: :job do
    let(:entry) { FactoryBot.build(:bulkrax_entry) }
    let(:importer_run) { FactoryBot.build(:bulkrax_importer_run) }

    before(:each) do
      allow(Bulkrax::Entry).to receive(:find).with(1).and_return(entry)
      allow(Bulkrax::ImporterRun).to receive(:find).with(2).and_return(importer_run)
      allow(entry).to receive(:build)
    end

    describe 'successful job' do
      before do
        allow(entry).to receive(:save).and_return(true)
      end
      it 'increments :processed_records' do
        expect(importer_run).to receive(:increment!).with(:processed_records)
        subject.perform(1, 2)
      end
    end
  end
end
