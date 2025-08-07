# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe DeleteWorkJob, type: :job do
    subject(:delete_work_job) { described_class.new }
    let(:entry) { create(:bulkrax_entry) }
    let(:importer_run) { create(:bulkrax_importer_run) }
    let(:factory) do
      Bulkrax::ObjectFactory.new(attributes: {},
                                 source_identifier_value: '123',
                                 work_identifier: :source,
                                 work_identifier_search_field: :source_identifier)
    end

    describe 'successful job object removed' do
      before do
        work = instance_double("Work")
        allow(work).to receive(:delete).and_return true
        allow(factory).to receive(:find).and_return(work)
        allow(entry).to receive(:factory).and_return(factory)
      end

      it 'increments :deleted_records' do
        expect(importer_run.enqueued_records).to eq(1)
        expect(importer_run.deleted_records).to eq(0)

        delete_work_job.perform(entry, importer_run)
        importer_run.reload

        expect(importer_run.enqueued_records).to eq(0)
        expect(importer_run.deleted_records).to eq(1)
      end
    end

    describe 'unsuccessful job when object not found' do
      before do
        allow(factory).to receive(:find).and_return(nil)
        allow(entry).to receive(:factory).and_return(factory)
        allow(factory).to receive(:delete).and_raise(StandardError, "Record not found")
        allow(entry).to receive(:set_status_info)
      end

      it 'raises an error and sets status info' do
        # Expect the error to be raised
        expect do
          delete_work_job.perform(entry, importer_run)
        end.to raise_error(StandardError, "Record not found")

        # Verify set_status_info was called with the error
        expect(entry).to have_received(:set_status_info).with(instance_of(StandardError))
      end

      it 'does not increment deleted_records or decrement enqueued_records' do
        expect(importer_run.enqueued_records).to eq(1)
        expect(importer_run.deleted_records).to eq(0)

        # Call perform but rescue the error
        begin
          delete_work_job.perform(entry, importer_run)
        rescue StandardError
          # Ignore the error
        end
        importer_run.reload

        # Counters should remain unchanged
        expect(importer_run.enqueued_records).to eq(1)
        expect(importer_run.deleted_records).to eq(0)
      end
    end
  end
end
