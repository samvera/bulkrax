# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe 'Jobs that keep raising until their retries run out', type: :job do
    include ActiveJob::TestHelper

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
  end
end
