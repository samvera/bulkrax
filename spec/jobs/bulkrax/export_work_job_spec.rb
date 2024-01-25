# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ExportWorkJob, type: :job do
    subject(:export_work_job) { described_class.new }
    let(:exporter) { create(:bulkrax_exporter, :all) }
    let(:entry) { create(:bulkrax_entry, importerexporter: exporter) }
    let(:exporter_run) { create(:bulkrax_exporter_run, exporter: exporter) }

    before do
      allow(Bulkrax::Entry).to receive(:find).with(1).and_return(entry)
      allow(entry).to receive(:build)
    end

    describe 'successful job' do
      it 'increments :processed_records' do
        expect(exporter_run.processed_records).to eq(0)

        export_work_job.perform(entry.id, exporter_run.id)
        exporter_run.reload

        expect(exporter_run.processed_records).to eq(1)
      end

      it 'decrements :enqueued_records' do
        expect(exporter_run.enqueued_records).to eq(1)

        export_work_job.perform(entry.id, exporter_run.id)
        exporter_run.reload

        expect(exporter_run.enqueued_records).to eq(0)
      end

      it "doesn't change unrelated counters" do
        expect(exporter_run.failed_records).to eq(0)
        expect(exporter_run.deleted_records).to eq(0)

        export_work_job.perform(1, exporter_run.id)
        exporter_run.reload

        expect(exporter_run.failed_records).to eq(0)
        expect(exporter_run.deleted_records).to eq(0)
      end
    end
  end
end
