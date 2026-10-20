# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ScheduleRelationshipsJob, type: :job do
    include ActiveSupport::Testing::TimeHelpers

    subject(:job) { described_class.new }

    let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }
    let(:run) { importer.importer_runs.create!(total_work_entries: 2, enqueued_records: 2) }
    let(:finished_entry) { FactoryBot.create(:bulkrax_csv_entry, identifier: 'finished', importerexporter: importer) }
    let(:late_entry) { FactoryBot.create(:bulkrax_csv_entry, identifier: 'late', importerexporter: importer) }

    def finish_late_entry
      PendingRelationship.create!(importer_run_id: run.id, parent_id: 'parent-2', child_id: 'late')
      late_entry.set_status_info(nil, run)
    end

    def next_check_in
      check = ActiveJob::Base.queue_adapter.enqueued_jobs.reverse.find { |enqueued| enqueued[:job] == described_class }
      Time.zone.at(check[:at]) - Time.current
    end

    before do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      finished_entry.set_status_info('Pending', run)
      finished_entry.set_status_info(nil, run)
      late_entry.set_status_info('Pending', run)
      PendingRelationship.create!(importer_run_id: run.id, parent_id: 'parent-1', child_id: 'finished')
    end

    context 'when an entry the parser created is still Pending' do
      it 'checks again in five minutes' do
        expect { job.perform(importer_id: importer.id) }
          .to have_enqueued_job(described_class).with(importer_id: importer.id)
        expect(next_check_in).to be_within(5.seconds).of(5.minutes)
      end

      it 'does not create any relationships yet' do
        expect { job.perform(importer_id: importer.id) }
          .not_to have_enqueued_job(CreateRelationshipsJob)
      end
    end

    context 'when every entry has finished' do
      before { finish_late_entry }

      it 'creates the relationships for every parent' do
        expect { job.perform(importer_id: importer.id) }
          .to have_enqueued_job(CreateRelationshipsJob).with(parent_identifier: 'parent-1', importer_run_id: run.id)
          .and have_enqueued_job(CreateRelationshipsJob).with(parent_identifier: 'parent-2', importer_run_id: run.id)
      end

      it 'does not check again' do
        expect { job.perform(importer_id: importer.id) }.not_to have_enqueued_job(described_class)
      end
    end

    context 'when the run started long ago but entries are still finishing' do
      before { run.update!(created_at: 3.days.ago) }

      it 'keeps waiting' do
        expect { job.perform(importer_id: importer.id) }.not_to have_enqueued_job(CreateRelationshipsJob)
        expect(next_check_in).to be_within(5.seconds).of(5.minutes)
      end
    end

    context 'when no entry has recorded a status for 24 hours' do
      it 'creates the relationships that are ready' do
        travel(25.hours) do
          expect { job.perform(importer_id: importer.id) }
            .to have_enqueued_job(CreateRelationshipsJob).with(parent_identifier: 'parent-1', importer_run_id: run.id)
        end
      end

      it 'keeps checking every hour and logs the entries still Pending' do
        allow(Rails.logger).to receive(:warn)
        travel(25.hours) do
          job.perform(importer_id: importer.id)
          expect(next_check_in).to be_within(5.seconds).of(1.hour)
        end
        expect(Rails.logger).to have_received(:warn).with(/importer #{importer.id}.*1 entry still Pending/)
      end

      it 'does not count entries of other importers, or the importer itself, finishing' do
        other_importer = FactoryBot.create(:bulkrax_importer_csv, name: 'Other import')
        other_entry = FactoryBot.create(:bulkrax_csv_entry, identifier: 'other', importerexporter: other_importer)
        travel(25.hours) do
          other_entry.set_status_info(nil, other_importer.importer_runs.create!)
          importer.set_status_info(nil, run)
          expect { job.perform(importer_id: importer.id) }
            .to have_enqueued_job(CreateRelationshipsJob).with(parent_identifier: 'parent-1', importer_run_id: run.id)
        end
      end

      it 'does not count a relationship error as an entry finishing' do
        travel(25.hours) do
          finished_entry.set_status_info('Parent record parent-1 not yet available for creating relationships with children records.', run)
          expect { job.perform(importer_id: importer.id) }
            .to have_enqueued_job(CreateRelationshipsJob).with(parent_identifier: 'parent-1', importer_run_id: run.id)
        end
      end

      context 'with a relationship that already failed' do
        before do
          failed = PendingRelationship.create!(importer_run_id: run.id, parent_id: 'finished', child_id: 'missing-child')
          failed.update!(status_message: 'Could not find child record missing-child')
        end

        it 'does not retry it while entries are still Pending' do
          travel(25.hours) do
            expect { job.perform(importer_id: importer.id) }
              .not_to have_enqueued_job(CreateRelationshipsJob).with(hash_including(parent_identifier: 'finished'))
          end
        end

        it 'retries it once no entry is Pending' do
          finish_late_entry
          expect { job.perform(importer_id: importer.id) }
            .to have_enqueued_job(CreateRelationshipsJob).with(parent_identifier: 'finished', importer_run_id: run.id)
        end
      end

      context 'with relationships that are not ready' do
        before do
          PendingRelationship.create!(importer_run_id: run.id, parent_id: 'existing-record-1', child_id: 'finished')
          PendingRelationship.create!(importer_run_id: run.id, parent_id: 'finished', child_id: 'late')
          PendingRelationship.create!(importer_run_id: run.id, parent_id: 'late', child_id: 'finished')
        end

        it 'relates parents whose children have all finished, including records from before this import' do
          travel(25.hours) do
            expect { job.perform(importer_id: importer.id) }
              .to have_enqueued_job(CreateRelationshipsJob).with(parent_identifier: 'parent-1', importer_run_id: run.id)
              .and have_enqueued_job(CreateRelationshipsJob).with(parent_identifier: 'existing-record-1', importer_run_id: run.id)
          end
        end

        it 'holds back parents that are Pending or still have a Pending child' do
          travel(25.hours) do
            expect { job.perform(importer_id: importer.id) }
              .not_to have_enqueued_job(CreateRelationshipsJob).with(hash_including(parent_identifier: 'finished'))
            expect { job.perform(importer_id: importer.id) }
              .not_to have_enqueued_job(CreateRelationshipsJob).with(hash_including(parent_identifier: 'late'))
          end
        end
      end

      it 'relates an entry that finishes later, then stops checking' do
        travel(25.hours) { job.perform(importer_id: importer.id) }
        travel(26.hours) do
          finish_late_entry
          expect { job.perform(importer_id: importer.id) }
            .to have_enqueued_job(CreateRelationshipsJob).with(parent_identifier: 'parent-2', importer_run_id: run.id)
          expect { job.perform(importer_id: importer.id) }.not_to have_enqueued_job(described_class)
        end
      end
    end

    context 'when no entry has recorded a status for 7 days' do
      it 'creates the relationships that are ready' do
        travel(8.days) do
          expect { job.perform(importer_id: importer.id) }
            .to have_enqueued_job(CreateRelationshipsJob).with(parent_identifier: 'parent-1', importer_run_id: run.id)
        end
      end

      it 'stops checking and logs an error naming the entries still Pending' do
        allow(Rails.logger).to receive(:error)
        travel(8.days) do
          expect { job.perform(importer_id: importer.id) }.not_to have_enqueued_job(described_class)
        end
        expect(Rails.logger).to have_received(:error).with(/importer #{importer.id}.*1 entry still Pending/)
      end
    end

    context 'when the Pending entries have never recorded a status' do
      before { Status.delete_all }

      it 'keeps waiting while the run is recent' do
        expect { job.perform(importer_id: importer.id) }.not_to have_enqueued_job(CreateRelationshipsJob)
      end

      it 'creates the relationships that are ready 24 hours after the run started' do
        run.update!(created_at: 25.hours.ago)
        expect { job.perform(importer_id: importer.id) }
          .to have_enqueued_job(CreateRelationshipsJob).with(parent_identifier: 'parent-1', importer_run_id: run.id)
      end
    end
  end
end
