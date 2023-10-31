# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ImportWorkJob, type: :job do
    subject(:import_work_job) { described_class.new }
    let(:importer_run_id) { 2 }
    let(:entry) { FactoryBot.build(:bulkrax_entry) }
    let(:importer_run) { FactoryBot.create(:bulkrax_importer_run, id: importer_run_id) }

    before do
      allow(Bulkrax::Entry).to receive(:find).with(1).and_return(entry)
    end

    describe 'successful job' do
      before do
        allow(entry).to receive(:collections_created?).and_return(true)
        allow(entry).to receive(:build).and_return(instance_of(Work))
        allow(entry).to receive(:status).and_return('Complete')
      end

      it 'increments :processed_records' do
        expect(importer_run.processed_records).to eq(0)

        import_work_job.perform(1, importer_run_id)
        importer_run.reload

        expect(importer_run.processed_records).to eq(1)
      end

      it 'increments :processed_works' do
        expect(importer_run.processed_works).to eq(0)

        import_work_job.perform(1, importer_run_id)
        importer_run.reload

        expect(importer_run.processed_works).to eq(1)
      end

      it 'decrements :enqueued_records' do
        expect(importer_run.enqueued_records).to eq(1)

        import_work_job.perform(1, importer_run_id)
        importer_run.reload

        expect(importer_run.enqueued_records).to eq(0)
      end

      it "doesn't change unrelated counters" do
        expect(importer_run.failed_records).to eq(0)
        expect(importer_run.deleted_records).to eq(0)
        expect(importer_run.processed_collections).to eq(0)
        expect(importer_run.failed_collections).to eq(0)
        expect(importer_run.processed_relationships).to eq(0)
        expect(importer_run.failed_relationships).to eq(0)
        expect(importer_run.processed_file_sets).to eq(0)
        expect(importer_run.failed_file_sets).to eq(0)
        expect(importer_run.failed_works).to eq(0)

        import_work_job.perform(1, importer_run_id)
        importer_run.reload

        expect(importer_run.failed_records).to eq(0)
        expect(importer_run.deleted_records).to eq(0)
        expect(importer_run.processed_collections).to eq(0)
        expect(importer_run.failed_collections).to eq(0)
        expect(importer_run.processed_relationships).to eq(0)
        expect(importer_run.failed_relationships).to eq(0)
        expect(importer_run.processed_file_sets).to eq(0)
        expect(importer_run.failed_file_sets).to eq(0)
        expect(importer_run.failed_works).to eq(0)
      end
    end

    describe 'unsuccessful job - collections not created' do
      before do
        allow(entry).to receive(:build_for_importer).and_raise(CollectionsCreatedError)
      end

      it 'does not change counters' do
        expect(importer_run.processed_records).to eq(0)
        expect(importer_run.processed_works).to eq(0)
        expect(importer_run.failed_records).to eq(0)
        expect(importer_run.failed_works).to eq(0)

        import_work_job.perform(1, importer_run_id)
        importer_run.reload

        expect(importer_run.processed_records).to eq(0)
        expect(importer_run.processed_works).to eq(0)
        expect(importer_run.failed_records).to eq(0)
        expect(importer_run.failed_works).to eq(0)
      end

      it 'reschedules the job' do
        expect(import_work_job).to receive(:reschedule) # rubocop:disable RSpec/SubjectStub
        import_work_job.perform(1, importer_run_id)
      end
    end

    describe 'unsuccessful job - error caught by build' do
      before do
        allow(entry).to receive(:build).and_return(nil)
      end

      it 'increments :failed_records and :failed_works' do
        expect(importer_run.failed_records).to eq(0)
        expect(importer_run.failed_works).to eq(0)

        import_work_job.perform(1, importer_run_id)
        importer_run.reload

        expect(importer_run.failed_records).to eq(1)
        expect(importer_run.failed_works).to eq(1)
      end

      it 'decrements :enqueued_records' do
        expect(importer_run.enqueued_records).to eq(1)

        import_work_job.perform(1, importer_run_id)
        importer_run.reload

        expect(importer_run.enqueued_records).to eq(0)
      end
    end

    describe 'unsuccessful job - custom error raised by build' do
      before do
        allow(entry).to receive(:build).and_raise(OAIError)
      end

      it 'does not increment :failed_records or :failed_works' do
        expect(importer_run.failed_records).to eq(0)
        expect(importer_run.failed_works).to eq(0)

        expect { import_work_job.perform(1, importer_run_id) }.to raise_error(OAIError)
        importer_run.reload

        expect(importer_run.failed_records).to eq(0)
        expect(importer_run.failed_works).to eq(0)
      end

      it 'does not decrement :enqueued_records' do
        expect(importer_run.enqueued_records).to eq(1)

        expect { import_work_job.perform(1, importer_run_id) }.to raise_error(OAIError)
        importer_run.reload

        expect(importer_run.enqueued_records).to eq(1)
      end
    end
  end
end
