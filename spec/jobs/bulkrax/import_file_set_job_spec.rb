# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ImportFileSetJob, type: :job do
    subject(:import_file_set_job) { described_class.new }
    let(:importer) { create(:bulkrax_importer_csv_complex) }
    let(:importer_run) { create(:bulkrax_importer_run, importer: importer) }
    let(:entry) { create(:bulkrax_csv_entry_file_set, :with_file_set_metadata, importerexporter: importer) }
    let(:factory) { instance_double(ObjectFactory) }

    describe 'is capable of looking up records dynamically' do
      include_examples 'dynamic record lookup'
    end

    before do
      allow(Entry).to receive(:find).with(entry.id).and_return(entry)
      allow(::Hyrax.config).to receive(:curation_concerns).and_return([Work])
      allow(::Work).to receive(:where).and_return([])
      allow(importer.parser).to receive(:path_to_files).with(filename: 'removed.png').and_return('spec/fixtures/removed.png')
    end

    describe '#perform' do
      context 'when the entry has a parent identifier' do
        before do
          allow(::Collection).to receive(:where).and_return([])
          allow(entry).to receive(:related_parents_raw_mapping).and_return('parents')
          allow(entry).to receive(:related_parents_parsed_mapping).and_return('parents')
          allow(entry).to receive(:factory).and_return(factory)
          entry.raw_metadata['parents'] = 'work_1'
          allow(factory).to receive(:run!)
        end

        context 'when the parent work has been created' do
          before do
            allow(import_file_set_job).to receive(:validate_parent!).and_return(nil)
          end

          it 'builds the entry successfully' do
            expect(entry).to receive(:build)
            expect(entry).to receive(:save!)

            import_file_set_job.perform(entry.id, importer_run.id)
          end

          it "runs the entry's factory" do
            expect(factory).to receive(:run!)

            import_file_set_job.perform(entry.id, importer_run.id)
          end

          it 'increments :processed_records and :processed_file_sets' do
            expect(importer_run.processed_records).to eq(0)
            expect(importer_run.processed_file_sets).to eq(0)

            import_file_set_job.perform(entry.id, importer_run.id)
            importer_run.reload

            expect(importer_run.processed_records).to eq(1)
            expect(importer_run.processed_file_sets).to eq(1)
          end

          it 'decrements :enqueued_records' do
            expect(importer_run.enqueued_records).to eq(1)

            import_file_set_job.perform(entry.id, importer_run.id)
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
            expect(importer_run.failed_file_sets).to eq(0)
            expect(importer_run.processed_works).to eq(0)
            expect(importer_run.failed_works).to eq(0)

            import_file_set_job.perform(entry.id, importer_run.id)
            importer_run.reload

            expect(importer_run.failed_records).to eq(0)
            expect(importer_run.deleted_records).to eq(0)
            expect(importer_run.processed_collections).to eq(0)
            expect(importer_run.failed_collections).to eq(0)
            expect(importer_run.processed_relationships).to eq(0)
            expect(importer_run.failed_relationships).to eq(0)
            expect(importer_run.failed_file_sets).to eq(0)
            expect(importer_run.processed_works).to eq(0)
            expect(importer_run.failed_works).to eq(0)
          end
        end

        context 'when the parent work is not found or has not been created yet' do
          before do
            allow(import_file_set_job).to receive(:find_record).and_return(nil)
          end

          context "when the entry's :import_attempts are less than 6" do
            it "increments the entry's :import_attempts" do
              expect { import_file_set_job.perform(entry.id, importer_run.id) }
                .to change(entry, :import_attempts).by(1)
            end

            it 'does not throw any errors' do
              expect { import_file_set_job.perform(entry.id, importer_run.id) }.not_to raise_error
            end

            it "does not update any of importer run's counters" do
              expect(ImporterRun).not_to receive(:increment_counter)
              expect(ImporterRun).not_to receive(:decrement_enqueued_records)

              import_file_set_job.perform(entry.id, importer_run.id)
            end

            it 'reschedules the job to try again after five minutes' do
              configured_job = instance_double(::ActiveJob::ConfiguredJob)
              # #set initializes an ActiveJob::ConfiguredJob
              expect(described_class).to receive(:set).with(wait: 5.minutes).and_return(configured_job)
              expect(configured_job).to receive(:perform_later).with(entry.id, importer_run.id).once

              import_file_set_job.perform(entry.id, importer_run.id)
            end

            it "waits long enough to outlast the parent work's own retries" do
              configured_job = instance_double(::ActiveJob::ConfiguredJob, perform_later: true)
              waits = []
              allow(described_class).to receive(:set) do |wait:|
                waits << wait.to_i
                configured_job
              end

              5.times { import_file_set_job.perform(entry.id, importer_run.id) }

              expect(waits).to eq([5, 10, 20, 40, 80].map { |minutes| minutes.minutes.to_i })
            end
          end

          context "when the entry's :import_attempts are 6 or greater" do
            before do
              entry.import_attempts = 5 # before failed attempt
              entry.save!
            end

            it "increments the entry's :import_attempts" do
              expect { import_file_set_job.perform(entry.id, importer_run.id) }
                .to change(entry, :import_attempts).by(1)
            end

            it 'logs a MissingParentError on the entry' do
              import_file_set_job.perform(entry.id, importer_run.id)

              expect(entry.reload.current_status).to have_attributes(status_message: 'Failed', error_class: 'Bulkrax::MissingParentError')
            end

            it 'counts the record as finished and failed' do
              import_file_set_job.perform(entry.id, importer_run.id)

              expect(importer_run.reload)
                .to have_attributes(enqueued_records: 0, failed_records: 1, failed_file_sets: 1)
            end

            it 'does not reschedule the job' do
              expect(described_class).not_to receive(:set)

              import_file_set_job.perform(entry.id, importer_run.id)
            end
          end
        end

        context 'when the parent identifier does not reference a work' do
          before do
            allow(import_file_set_job).to receive(:find_record).and_return([nil, non_work])
          end

          shared_examples 'a file set with an invalid parent' do
            it 'fails the entry without retrying' do
              expect { import_file_set_job.perform(entry.id, importer_run.id) }.not_to raise_error

              expect(entry.reload.current_status)
                .to have_attributes(error_class: 'Bulkrax::InvalidParentError', error_message: /not an valid\/available work type/)
            end

            it 'counts the record as finished and failed' do
              import_file_set_job.perform(entry.id, importer_run.id)

              expect(importer_run.reload)
                .to have_attributes(enqueued_records: 0, failed_records: 1, failed_file_sets: 1)
            end
          end

          context 'when it references a collection' do
            let(:non_work) { Bulkrax.collection_model_class.new }

            it_behaves_like 'a file set with an invalid parent'
          end

          context 'when it references a file set' do
            let(:non_work) { Bulkrax.file_model_class.new }

            it_behaves_like 'a file set with an invalid parent'
          end
        end
      end

      context 'when the entry does not have a parent identifier' do
        it 'builds the entry unsuccessfully' do
          expect(entry).to receive(:build)

          import_file_set_job.perform(entry.id, importer_run.id)

          expect(entry.reload.succeeded?).to eq(nil)
        end

        it "does not run the entry's factory" do
          expect(factory).not_to receive(:run!)

          import_file_set_job.perform(entry.id, importer_run.id)
        end

        it 'increments :failed_records and :failed_file_sets' do
          expect(importer_run.failed_records).to eq(0)
          expect(importer_run.failed_file_sets).to eq(0)

          import_file_set_job.perform(entry.id, importer_run.id)
          importer_run.reload

          expect(importer_run.failed_records).to eq(1)
          expect(importer_run.failed_file_sets).to eq(1)
        end

        it 'decrements :enqueued_records' do
          expect(importer_run.enqueued_records).to eq(1)

          import_file_set_job.perform(entry.id, importer_run.id)
          importer_run.reload

          expect(importer_run.enqueued_records).to eq(0)
        end

        it "doesn't change unrelated counters" do
          expect(importer_run.processed_records).to eq(0)
          expect(importer_run.deleted_records).to eq(0)
          expect(importer_run.processed_collections).to eq(0)
          expect(importer_run.failed_collections).to eq(0)
          expect(importer_run.processed_relationships).to eq(0)
          expect(importer_run.failed_relationships).to eq(0)
          expect(importer_run.processed_file_sets).to eq(0)
          expect(importer_run.processed_works).to eq(0)
          expect(importer_run.failed_works).to eq(0)

          import_file_set_job.perform(entry.id, importer_run.id)
          importer_run.reload

          expect(importer_run.processed_records).to eq(0)
          expect(importer_run.deleted_records).to eq(0)
          expect(importer_run.processed_collections).to eq(0)
          expect(importer_run.failed_collections).to eq(0)
          expect(importer_run.processed_relationships).to eq(0)
          expect(importer_run.failed_relationships).to eq(0)
          expect(importer_run.processed_file_sets).to eq(0)
          expect(importer_run.processed_works).to eq(0)
          expect(importer_run.failed_works).to eq(0)
        end
      end
    end
  end
end
