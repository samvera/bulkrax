require 'rails_helper'

module Bulkrax
  RSpec.describe ExporterJob, type: :job do
    let(:exporter) { FactoryBot.create(:bulkrax_exporter) }
    let(:bulkrax_exporter_run) { FactoryBot.create(:bulkrax_exporter_run, exporter: exporter) }

    before do
      allow(Bulkrax::Exporter).to receive(:find).with(1).and_return(exporter)
      allow(exporter).to receive(:exporter_runs).and_return([bulkrax_exporter_run])
      allow(exporter).to receive(:mapping).and_return("title" => {})
    end

    describe 'successful job' do
      it 'calls export' do
        expect(exporter).to receive(:export)
        subject.perform(1)
      end
    end
  end
end
