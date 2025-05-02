# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe CreateRelationshipsJob, type: :job do
    let(:create_relationships_job) { described_class.new }
    let(:importer) { FactoryBot.create(:bulkrax_importer_csv_complex) }
    let(:ability) { instance_double(Ability) }

    # create objects
    let(:collection1) { build(:collection) }
    let(:collection2) { build(:collection) }
    let(:work1) { build(:work) }
    let(:work2) { build(:work) }

    # create entries
    let(:collection1_entry) { create(:bulkrax_csv_entry_collection, importerexporter: importer) }
    let(:collection2_entry) { create(:bulkrax_csv_entry_collection, importerexporter: importer) }
    let(:work1_entry) { create(:bulkrax_csv_entry_work, importerexporter: importer) }
    let(:work2_entry) { create(:bulkrax_csv_entry_work, importerexporter: importer) }

    before do
      allow(ImporterRun).to receive(:update_counters).and_return(true)
      allow(Ability).to receive(:new).and_return(ability)
      allow(ability).to receive(:authorize!).and_return(true)
      # The real work happens in the object factory. Each object factory
      # should have its own tests to verify that it does the right thing.
      allow(Bulkrax.object_factory).to receive(:add_resource_to_collection).and_return(true)
      allow(Bulkrax.object_factory).to receive(:update_index).and_return(true)
      allow(Bulkrax.object_factory).to receive(:publish).and_return(true)
      allow(create_relationships_job).to receive(:reschedule)
      allow(Bulkrax.object_factory).to receive(:add_child_to_parent_work).and_return(true)
      allow(Bulkrax.object_factory).to receive(:save!).and_return(true)
    end

    around do |spec|
      old = Bulkrax.object_factory
      Bulkrax.object_factory = Bulkrax::MockObjectFactory
      spec.run
      Bulkrax.object_factory = old
    end

    describe 'is capable of looking up records dynamically' do
      include_examples 'dynamic record lookup'
    end

    describe '#perform' do
      subject(:perform) do
        create_relationships_job.perform(
          parent_identifier: parent_identifier, # source_identifier
          importer_run_id: importer.current_run.id
        )
      end

      context 'when adding a child work to a parent collection' do
        let(:pending_rel_test) { create(:pending_relationship,
                                        importer_run_id: importer.current_run.id,
                                        parent_id: parent_identifier,
                                        child_id: work1_entry.identifier,
                                        order: 1) }
        let(:parent_identifier) { collection1_entry.identifier }

        before do
          allow(create_relationships_job).to receive(:find_record).with(parent_identifier, importer.current_run.id).and_return([collection1_entry, collection1])
          allow(create_relationships_job).to receive(:find_record).with(work1_entry.identifier, importer.current_run.id).and_return([work1_entry, work1])
          pending_rel_test
        end

        it 'calls the object factory to assign the child work to the collection' do
          expect(Bulkrax.object_factory).to receive(:add_resource_to_collection).with(collection: collection1, resource: work1, user: importer.current_run.user)
          expect(Bulkrax.object_factory).to receive(:update_index).with(resources: [collection1])
          expect(Bulkrax.object_factory).to receive(:publish).with(event: 'object.membership.updated', object: collection1, user: importer.current_run.user)
          expect(ImporterRun).to receive(:update_counters).with(importer.current_run.id, processed_relationships: 1)
          perform
        end

        it 'deletes the pending relationship' do
          expect { perform }.to change(Bulkrax::PendingRelationship, :count).by(-1)
        end

        it 'does not reschedule the job' do
          perform
          expect(create_relationships_job).not_to have_received(:reschedule)
        end
      end

      context 'when adding a child collection to a parent collection' do
        let(:pending_rel_test) { create(:pending_relationship,
                                        importer_run_id: importer.current_run.id,
                                        parent_id: parent_identifier,
                                        child_id: collection2_entry.identifier,
                                        order: 1) }
        let(:parent_identifier) { collection1_entry.identifier }

        before do
          allow(create_relationships_job).to receive(:find_record).with(parent_identifier, importer.current_run.id).and_return([collection1_entry, collection1])
          allow(create_relationships_job).to receive(:find_record).with(work1_entry.identifier, importer.current_run.id).and_return([collection2_entry, collection2])
          pending_rel_test
        end

        it 'calls the object factory to assign the child collection to the collection' do
          expect(Bulkrax.object_factory).to receive(:add_resource_to_collection).with(collection: collection1, resource: collection2, user: importer.current_run.user)
          expect(Bulkrax.object_factory).to receive(:update_index).with(resources: [collection1])
          expect(Bulkrax.object_factory).to receive(:publish).with(event: 'object.membership.updated', object: collection1, user: importer.current_run.user)
          expect(ImporterRun).to receive(:update_counters).with(importer.current_run.id, processed_relationships: 1)
          perform
        end

        it 'deletes the pending relationship' do
          expect { perform }.to change(Bulkrax::PendingRelationship, :count).by(-1)
        end

        it 'does not reschedule the job' do
          perform
          expect(create_relationships_job).not_to have_received(:reschedule)
        end
      end

      context 'when adding a child work to a parent work' do
        let(:pending_rel_test) { create(:pending_relationship,
                                        importer_run_id: importer.current_run.id,
                                        parent_id: parent_identifier,
                                        child_id: work2_entry.identifier,
                                        order: 1) }
        let(:parent_identifier) { work1_entry.identifier }
        let(:update_child_records_works_file_sets?) { false }

        before do
          allow(create_relationships_job).to receive(:find_record).with(parent_identifier, importer.current_run.id).and_return([work1_entry, work1])
          allow(create_relationships_job).to receive(:find_record).with(work2_entry.identifier, importer.current_run.id).and_return([work2_entry, work2])
          pending_rel_test
        end

        it 'calls the object factory to assign the child work to the parent_work' do
          expect(Bulkrax.object_factory).to receive(:add_child_to_parent_work).with(parent: work1, child: work2)
          expect(Bulkrax.object_factory).to receive(:save!).with(resource: work1, user: importer.current_run.user)
          expect(Bulkrax.object_factory).not_to receive(:update_index_for_file_sets_of)
          expect(ImporterRun).to receive(:update_counters).with(importer.current_run.id, processed_relationships: 1)
          perform
        end

        it 'deletes the pending relationship' do
          expect { perform }.to change(Bulkrax::PendingRelationship, :count).by(-1)
        end

        it 'does not reschedule the job' do
          perform
          expect(create_relationships_job).not_to have_received(:reschedule)
        end
      end

      context 'when adding a child collection to a parent work' do
        let(:pending_rel_test) { create(:pending_relationship,
                                        importer_run_id: importer.current_run.id,
                                        parent_id: parent_identifier,
                                        child_id: collection1_entry.identifier,
                                        order: 1) }
        let(:parent_identifier) { work1_entry.identifier }

        before do
          allow(create_relationships_job).to receive(:find_record).with(parent_identifier, importer.current_run.id).and_return([work1_entry, work1])
          allow(create_relationships_job).to receive(:find_record).with(collection1_entry.identifier, importer.current_run.id).and_return([collection1_entry, collection1])
          pending_rel_test
        end

        it 'logs an error to the parent entry' do
          expect { perform }.to change(work1_entry, :failed?).to(true)
        end

        it 'increments current importer run\'s :failed_relationships' do
          expect(ImporterRun).to receive(:update_counters).with(importer.current_run.id, failed_relationships: 1)
          perform
        end
      end

      context 'when adding a child record that is not found' do
        let(:pending_rel_test) { create(:pending_relationship,
                                        importer_run_id: importer.current_run.id,
                                        parent_id: parent_identifier,
                                        child_id: child_id,
                                        order: 1) }
        let(:parent_identifier) { collection1_entry.identifier }
        let(:child_id) { 'not_found' }

        before do
        allow(create_relationships_job).to receive(:find_record).with(parent_identifier, importer.current_run.id).and_return([work1_entry, work1])
        allow(create_relationships_job).to receive(:find_record).with(child_id, importer.current_run.id).and_return([nil, nil])
        pending_rel_test
        end

        it 'reschedules the job' do
          expect(ImporterRun).to receive(:update_counters).with(importer.current_run.id, failed_relationships: 1)
          expect(create_relationships_job).to receive(:reschedule).with(parent_identifier: parent_identifier, importer_run_id: importer.current_run.id, run_user: importer.current_run.user, failure_count: 1)
          result = perform
          # Expect the result to be an array containing one RuntimeError
          expect(result).to match([an_instance_of(RuntimeError)])
        end
      end

      context 'when adding a parent record that is not found' do
        let(:pending_rel_test) { create(:pending_relationship,
                                        importer_run_id: importer.current_run.id,
                                        parent_id: parent_identifier,
                                        child_id: child_id,
                                        order: 1) }
        let(:parent_identifier) { 'not_found' }
        let(:child_id) { work1_entry.identifier }

        before do
        allow(create_relationships_job).to receive(:find_record).with(parent_identifier, importer.current_run.id).and_return([nil, nil])
        allow(create_relationships_job).to receive(:find_record).with(child_id, importer.current_run.id).and_return([work1_entry, work1])
        pending_rel_test
        end

        it 'reschedules the job' do
          expect(ImporterRun).to receive(:update_counters).with(importer.current_run.id, failed_relationships: 1)
          expect(create_relationships_job).to receive(:reschedule).with(parent_identifier: parent_identifier, importer_run_id: importer.current_run.id, run_user: importer.current_run.user, failure_count: 1)
          result = perform
          expect(result).to eq(["Parent record #{parent_identifier} not yet available for creating relationships with children records."])
        end
      end
    end
  end
end
