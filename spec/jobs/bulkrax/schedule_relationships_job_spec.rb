# frozen_string_literal: true

require 'rails_helper'

RSpec::Matchers.define_negated_matcher :not_have_enqueued_job, :have_enqueued_job

module Bulkrax
  RSpec.describe ScheduleRelationshipsJob, type: :job do
    subject(:job) { described_class.new }

    let(:importer) { FactoryBot.create(:bulkrax_importer) }
    let(:importer_run) { FactoryBot.create(:bulkrax_importer_run, importer: importer) }

    def entry_with_status(message)
      entry = FactoryBot.create(:bulkrax_entry, importerexporter: importer)
      FactoryBot.create(:bulkrax_status, statusable: entry, runnable: importer_run, status_message: message) if message
      entry
    end

    before { FactoryBot.create(:pending_relationship, importer_run: importer_run, parent_id: 'parent-1', child_id: 'child-1') }

    context 'when every entry has completed' do
      before { entry_with_status('Complete') }

      it 'schedules one relationship job per parent' do
        expect { job.perform(importer_id: importer.id) }
          .to have_enqueued_job(CreateRelationshipsJob).with(parent_identifier: 'parent-1', importer_run_id: importer_run.id)
      end
    end

    context 'when an entry has no status yet' do
      before { entry_with_status(nil) }

      it 'reschedules itself instead of scheduling relationships' do
        expect { job.perform(importer_id: importer.id) }
          .to have_enqueued_job(described_class).with(importer_id: importer.id)
          .and not_have_enqueued_job(CreateRelationshipsJob)
      end
    end

    context 'when an entry is still Pending' do
      before do
        entry_with_status('Complete')
        entry_with_status('Pending')
      end

      it 'reschedules itself, because the pending entry may still create relationships' do
        expect { job.perform(importer_id: importer.id) }
          .to have_enqueued_job(described_class).with(importer_id: importer.id)
          .and not_have_enqueued_job(CreateRelationshipsJob)
      end
    end
  end
end
