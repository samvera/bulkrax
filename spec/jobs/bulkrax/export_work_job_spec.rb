require 'rails_helper'

module Bulkrax
  RSpec.describe ExportWorkJob, type: :job do
    let(:entry) { FactoryBot.build(:bulkrax_entry) }
    let(:exporter_run) { FactoryBot.build(:bulkrax_exporter_run) }

    before do
      allow(Bulkrax::Entry).to receive(:find).with(1).and_return(entry)
      allow(Bulkrax::ExporterRun).to receive(:find).with(1).and_return(exporter_run)
      allow(entry).to receive(:build)
    end

    describe 'successful job' do
      before do
        allow(entry).to receive(:save).and_return(true)
      end
      it 'increments :processed_records' do
        expect(exporter_run).to receive(:increment!).with(:processed_records)
        subject.perform(1, 1)
      end
    end
  end
end
