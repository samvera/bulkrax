# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe 'Jobs that keep raising until their retries run out', type: :job do
    include ActiveJob::TestHelper
    include ActiveSupport::Testing::TimeHelpers

    let(:importer_run) { create(:bulkrax_importer_run, enqueued_records: 2) }
    let(:entry) { create(:bulkrax_csv_entry, importerexporter: importer_run.importer) }

    before do
      allow_any_instance_of(Entry).to receive(:build).and_raise(RuntimeError, 'Solr unavailable')
    end

    shared_examples 'an import job that counts the record as failed once' do |failed_type_counter|
      it 'counts the record as finished and failed exactly once' do
        perform_enqueued_jobs { described_class.perform_later(entry.id, importer_run.id) }

        expect(importer_run.reload)
          .to have_attributes(enqueued_records: 1, failed_records: 1, failed_type_counter => 1)
      end

      context 'when recording the importer status raises after a successful build' do
        before do
          allow_any_instance_of(Entry).to receive(:build) { |built| built.set_status_info('Complete') }
          allow_any_instance_of(Importer).to receive(:record_status).and_raise(RuntimeError, "status write failed")
        end

        it 'leaves the counts for the retry to apply' do
          expect { described_class.new.perform(entry.id, importer_run.id) }.to raise_error(RuntimeError, "status write failed")

          expect(importer_run.reload).to have_attributes(enqueued_records: 2, processed_records: 0)
        end
      end
    end

    describe ImportWorkJob do
      it_behaves_like 'an import job that counts the record as failed once', :failed_works

      it 'waits longer before each retry' do
        waits = []
        allow_any_instance_of(described_class).to receive(:retry_job).and_wrap_original do |original, *args, **options|
          waits << (args.first || options)[:wait].to_i
          original.call(*args, **options)
        end

        perform_enqueued_jobs { described_class.perform_later(entry.id, importer_run.id) }

        expect(waits).to eq([5, 10, 20, 40].map { |minutes| minutes.minutes.to_i })
      end

      context 'when it is the last record' do
        let(:importer_run) { create(:bulkrax_importer_run, enqueued_records: 1) }

        it 'marks the importer complete with failures' do
          perform_enqueued_jobs { described_class.perform_later(entry.id, importer_run.id) }

          expect(importer_run.importer.reload.status).to eq('Complete (with failures)')
        end
      end

      describe '#count_as_failed' do
        let(:error) { RuntimeError.new('Solr unavailable') }

        it 'still counts the record when its entry has been deleted' do
          described_class.new.count_as_failed(entry.tap(&:destroy).id, importer_run.id, error)

          expect(importer_run.reload).to have_attributes(enqueued_records: 1, failed_records: 1, failed_works: 1)
        end

        it 'rolls back the counts when recording the importer status raises' do
          allow_any_instance_of(Importer).to receive(:record_status).and_raise(RuntimeError, "status write failed")

          expect { described_class.new.count_as_failed(entry.id, importer_run.id, error) }.to raise_error(RuntimeError, "status write failed")
          expect(importer_run.reload).to have_attributes(enqueued_records: 2, failed_records: 0, failed_works: 0)
        end
      end
    end

    describe ImportCollectionJob do
      it_behaves_like 'an import job that counts the record as failed once', :failed_collections
    end

    describe ImportFileSetJob do
      it_behaves_like 'an import job that counts the record as failed once', :failed_file_sets
    end

    context "when the record's lock can't be taken" do
      let(:locker) { Class.new { include Bulkrax::Lockable }.new }
      let(:factory) { double('factory') }

      before do
        allow_any_instance_of(Entry).to receive(:build).and_call_original
        allow_any_instance_of(CsvEntry).to receive(:build_metadata)
        allow_any_instance_of(CsvEntry).to receive(:collections_created?).and_return(true)
        allow_any_instance_of(CsvEntry).to receive(:factory).and_return(factory)
        allow(factory).to receive(:run!) { locker.acquire_lock_for('locked-work') { nil } }
        allow_any_instance_of(Hyrax::LockManager).to receive(:lock).and_raise(Hyrax::LockManager::UnableToAcquireLockError)
      end

      shared_examples 'an import job that retries soon, then fails naming the locked record' do |failed_type_counter|
        it 'leaves the entry pending and uncounted while it waits to retry' do
          described_class.perform_now(entry.id, importer_run.id)

          expect(entry.reload.status).to eq('Pending')
          expect(importer_run.reload).to have_attributes(enqueued_records: 2, failed_records: 0)
        end

        it 'waits 1, 2, 4, 8 and then 16 minutes, plus some randomness, before each retry' do
          allow(Bulkrax::Lockable).to receive(:rand).and_return(7)
          waits = []
          allow_any_instance_of(described_class).to receive(:retry_job).and_wrap_original do |original, *args, **options|
            waits << (args.first || options)[:wait].to_i
            original.call(*args, **options)
          end

          perform_enqueued_jobs { described_class.perform_later(entry.id, importer_run.id) }

          expect(waits).to eq([1, 2, 4, 8, 16].map { |minutes| minutes.minutes.to_i + 7 })
        end

        it 'fails the entry, naming the locked record, once the retries run out' do
          perform_enqueued_jobs { described_class.perform_later(entry.id, importer_run.id) }

          expect(entry.reload.status).to eq('Failed')
          expect(entry.current_status.error_message).to include('locked-work')
          expect(importer_run.reload)
            .to have_attributes(enqueued_records: 1, failed_records: 1, failed_type_counter => 1)
        end
      end

      describe ImportFileSetJob do
        it_behaves_like 'an import job that retries soon, then fails naming the locked record', :failed_file_sets
      end

      describe ImportWorkJob do
        it_behaves_like 'an import job that retries soon, then fails naming the locked record', :failed_works
      end

      context 'when the lock is one Hyrax takes itself after saving part of the row' do
        before do
          allow(factory).to receive(:run!).and_raise(Hyrax::LockManager::UnableToAcquireLockError)
        end

        describe ImportFileSetJob do
          it 'fails the row without retrying' do
            expect { described_class.perform_now(entry.id, importer_run.id) }
              .not_to have_enqueued_job(described_class)

            expect(entry.reload.status).to eq('Failed')
          end
        end
      end
    end

    context 'when recording the importer status raises after a delete' do
      before do
        allow_any_instance_of(Entry).to receive(:factory).and_return(instance_double(ObjectFactory, delete: true))
        allow_any_instance_of(Importer).to receive(:record_status).and_raise(RuntimeError, 'status write failed')
      end

      it 'leaves the counts for the retry to apply' do
        expect { DeleteWorkJob.new.perform(entry, importer_run) }.to raise_error(RuntimeError, 'status write failed')

        expect(importer_run.reload).to have_attributes(enqueued_records: 2, deleted_records: 0)
      end
    end

    context 'when deleting the record keeps raising' do
      let(:factory) { instance_double(ObjectFactory, find: nil) }

      before do
        allow(factory).to receive(:delete).and_raise(RuntimeError, 'repository unavailable')
        allow_any_instance_of(Entry).to receive(:factory).and_return(factory)
      end

      describe DeleteWorkJob do
        it 'counts the record as finished and failed exactly once' do
          perform_enqueued_jobs { described_class.perform_later(entry, importer_run) }

          expect(importer_run.reload).to have_attributes(enqueued_records: 1, failed_records: 1)
        end

        it 'still counts the record when its entry is gone before the job runs' do
          job_data = described_class.new(entry, importer_run).serialize
          entry.destroy

          perform_enqueued_jobs { ActiveJob::Base.execute(job_data) }

          expect(importer_run.reload).to have_attributes(enqueued_records: 1, failed_records: 1)
        end
      end

      describe DeleteAndImportWorkJob do
        it 'counts the record as finished and failed exactly once' do
          perform_enqueued_jobs { described_class.perform_later(entry, importer_run) }

          expect(importer_run.reload).to have_attributes(enqueued_records: 1, failed_records: 1, failed_works: 1)
        end
      end
    end
  end
end
