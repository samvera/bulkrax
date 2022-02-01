# frozen_string_literal: true

require 'rails_helper'
require Rails.root.parent.parent.join('spec', 'models', 'concerns', 'bulkrax', 'dynamic_record_lookup_spec').to_s

module Bulkrax
  RSpec.describe ImportFileSetJob, type: :job do
    subject(:import_file_set_job) { described_class.new }
    let(:importer) { FactoryBot.create(:bulkrax_importer_csv_complex) }
    let(:importer_run) { importer.current_run }
    let(:entry) { create(:bulkrax_csv_entry_file_set, :with_file_set_metadata, importerexporter: importer) }
    let(:factory) { instance_double(ObjectFactory) }

    describe 'shared examples' do # TODO: remove or rename
      include_examples 'dynamic record lookup'
    end

    before do
      allow(Entry).to receive(:find).with(entry.id).and_return(entry)
      allow(ImporterRun).to receive(:find).with(importer_run.id).and_return(importer_run)
      allow(::Hyrax.config).to receive(:curation_concerns).and_return([Work])
      allow(::Work).to receive(:where).and_return([])
      allow(importer.parser).to receive(:path_to_files).and_return('spec/fixtures/')
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

          it "updates the importer run's counters" do
            expect(importer_run).to receive(:increment!).with(:processed_records).once
            expect(importer_run).to receive(:increment!).with(:processed_file_sets).once
            expect(importer_run).to receive(:decrement!).with(:enqueued_records).once

            expect(importer_run).not_to receive(:increment!).with(:failed_records)
            expect(importer_run).not_to receive(:increment!).with(:failed_file_sets)

            import_file_set_job.perform(entry.id, importer_run.id)
          end
        end

        context 'when the parent work is not found or has not been created yet' do
          before do
            allow(import_file_set_job).to receive(:find_record).and_return(nil)
          end

          context "when the entry's :import_attempts are less than 5" do
            it "increments the entry's :import_attempts" do
              expect { import_file_set_job.perform(entry.id, importer_run.id) }
                .to change(entry, :import_attempts).by(1)
            end

            it 'does not throw any errors' do
              expect { import_file_set_job.perform(entry.id, importer_run.id) }.not_to raise_error
            end

            it "does not update any of importer run's counters" do
              expect(importer_run).not_to receive(:increment!)
              expect(importer_run).not_to receive(:decrement!)
            end

            it 'reschedules the job to try again after a couple minutes' do
              configured_job = instance_double(::ActiveJob::ConfiguredJob)
              # #set initializes an ActiveJob::ConfiguredJob
              expect(described_class).to receive(:set).with(wait: 2.minutes).and_return(configured_job)
              expect(configured_job).to receive(:perform_later).with(entry.id, importer_run.id).once

              import_file_set_job.perform(entry.id, importer_run.id)
            end
          end

          context "when the entry's :import_attempts are 5 or greater" do
            before do
              entry.import_attempts = 4 # before failed attempt
              entry.save!
            end

            it "increments the entry's :import_attempts" do
              expect { import_file_set_job.perform(entry.id, importer_run.id) }
                .to change(entry, :import_attempts).by(1)
            end

            it 'logs a MissingParentError on the entry' do
              expect(entry).to receive(:status_info).with(instance_of(MissingParentError))

              import_file_set_job.perform(entry.id, importer_run.id)
            end

            it "only decrements the importer run's :enqueued_records counter" do
              expect(importer_run).not_to receive(:increment!)
              expect(importer_run).to receive(:decrement!).with(:enqueued_records).once

              import_file_set_job.perform(entry.id, importer_run.id)
            end

            it 'does not reschedule the job' do
              expect(described_class).not_to receive(:set)

              import_file_set_job.perform(entry.id, importer_run.id)
            end
          end
        end

        context 'when the parent identifier does not reference a work' do
          before do
            allow(import_file_set_job).to receive(:find_record).and_return(non_work)
          end

          context 'when it references a collection' do
            let(:non_work) { build(:collection) }

            it 'raises an error' do
              expect { import_file_set_job.perform(entry.id, importer_run.id) }
                .to raise_error(::StandardError, /not an valid\/available work type/)
            end
          end

          context 'when it references a file set' do
            let(:non_work) { instance_double(::FileSet) }

            it 'raises an error' do
              expect { import_file_set_job.perform(entry.id, importer_run.id) }
                .to raise_error(::StandardError, /not an valid\/available work type/)
            end
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

        it "updates the importer run's counters" do
          expect(importer_run).to receive(:increment!).with(:failed_records).once
          expect(importer_run).to receive(:increment!).with(:failed_file_sets).once
          expect(importer_run).to receive(:decrement!).with(:enqueued_records).once

          expect(importer_run).not_to receive(:increment!).with(:processed_records)
          expect(importer_run).not_to receive(:increment!).with(:processed_file_sets)

          import_file_set_job.perform(entry.id, importer_run.id)
        end
      end
    end
  end
end
