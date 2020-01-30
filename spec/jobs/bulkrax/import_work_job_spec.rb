# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ImportWorkJob, type: :job do
    subject(:import_work_job) { described_class.new }
    let(:entry) { FactoryBot.build(:bulkrax_entry) }
    let(:importer_run) { FactoryBot.build(:bulkrax_importer_run) }

    before do
      allow(Bulkrax::Entry).to receive(:find).with(1).and_return(entry)
      allow(Bulkrax::ImporterRun).to receive(:find).with(2).and_return(importer_run)
    end

    describe 'successful job' do
      before do
        allow(entry).to receive(:collections_created?).and_return(true)
        allow(entry).to receive(:build).and_return(instance_of(Work))
        allow(entry).to receive(:save!)
      end
      it 'increments :processed_records' do
        expect(importer_run).to receive(:increment!).with(:processed_records)
        expect(importer_run).to receive(:decrement!).with(:enqueued_records)
        import_work_job.perform(1, 2)
      end
    end

    describe 'unsuccessful job - collections not created' do
      before do
        allow(entry).to receive(:build_for_importer).and_raise(CollectionsCreatedError)
        allow(entry).to receive(:save!)
      end
      it 'does not call increment' do
        expect(importer_run).not_to receive(:increment!)
        expect(importer_run).not_to receive(:decrement!)
        import_work_job.perform(1, 2)
      end
      it 'reschedules the job' do
        expect(import_work_job).to receive(:reschedule) # rubocop:disable RSpec/SubjectStub
        import_work_job.perform(1, 2)
      end
    end

    describe 'unsuccessful job - error caught by build' do
      before do
        allow(entry).to receive(:build).and_return(nil)
        allow(entry).to receive(:save!)
      end
      it 'increments :failed_records' do
        expect(importer_run).to receive(:increment!).with(:failed_records)
        expect(importer_run).to receive(:decrement!).with(:enqueued_records)
        import_work_job.perform(1, 2)
      end
    end

    describe 'unsuccessful job - custom error raised by build' do
      before do
        allow(entry).to receive(:build).and_raise(OAIError)
      end
      it 'increments :failed_records' do
        expect { import_work_job.perform(1, 2) }.to raise_error(OAIError)
        expect(importer_run).not_to receive(:increment!).with(:failed_records)
        expect(importer_run).not_to receive(:decrement!).with(:enqueued_records)
      end
    end
  end
end
