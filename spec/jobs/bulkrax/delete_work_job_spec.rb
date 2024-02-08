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

    describe 'successful job object not found' do
      before do
        allow(factory).to receive(:find).and_return(nil)
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
  end
end
