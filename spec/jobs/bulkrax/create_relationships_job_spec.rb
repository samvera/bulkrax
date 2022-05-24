# frozen_string_literal: true

require 'rails_helper'
require Rails.root.parent.parent.join('spec', 'models', 'concerns', 'bulkrax', 'dynamic_record_lookup_spec').to_s

module Bulkrax
  RSpec.describe CreateRelationshipsJob, type: :job do
    subject(:create_relationships_job) { described_class.new }
    let(:importer) { FactoryBot.create(:bulkrax_importer_csv_complex) }
    let(:parent_entry) { create(:bulkrax_csv_entry_collection, importerexporter: importer) }
    let(:child_entry) { create(:bulkrax_csv_entry_work, importerexporter: importer) }
    let(:parent_record) { build(:collection) }
    let(:child_record) { build(:work) }
    let(:parent_factory) { instance_double(ObjectFactory, find: parent_record, run: parent_record) }
    let(:child_factory) { instance_double(ObjectFactory, find: child_record, run: child_record) }
    let(:pending_rel) { build(:pending_relationship_collection_parent) }
    let(:pending_rel_work) { build(:pending_relationship_work_parent) }

    before do
      allow(::Hyrax.config).to receive(:curation_concerns).and_return([Work])
      allow(Entry).to receive(:find_by).with({ identifier: child_entry.identifier, importerexporter_type: 'Bulkrax::Importer', importerexporter_id: importer.id }).and_return(child_entry)
      allow(Entry).to receive(:find_by).with({ identifier: parent_entry.identifier, importerexporter_type: 'Bulkrax::Importer', importerexporter_id: importer.id }).and_return(parent_entry)
      allow(parent_entry).to receive(:factory).and_return(parent_factory)
      allow(child_entry).to receive(:factory).and_return(child_factory)
    end

    describe 'is capable of looking up records dynamically' do
      include_examples 'dynamic record lookup'
    end

    describe '#perform' do
      context 'when adding a child work to a parent collection' do
        before do
          allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel])
        end

        context 'with a Bulkrax::Entry source_identifier' do
          it 'calls #collection_parent_work_child' do
            expect(create_relationships_job).to receive(:collection_parent_work_child)

            create_relationships_job.perform(
              parent_identifier: parent_entry.identifier, # source_identifier
              importer_run_id: importer.current_run.id
            )
          end

          it 'calls #add_member_objects on the parent record' do
            expect(parent_record).to receive(:add_member_objects).with([child_record.id])

            create_relationships_job.perform(
              parent_identifier: parent_entry.identifier,
              importer_run_id: importer.current_run.id
            )
          end

          it 'increments the processed relationships counter on the importer run' do
            allow(parent_record).to receive(:add_member_objects)
            create_relationships_job.perform(
              parent_identifier: parent_entry.identifier,
              importer_run_id: importer.current_run.id
            )
            # TODO: current_run.reload doesn't make sense, need to investigate further
            expect(importer.current_run.reload.processed_relationships).to eq(1)
          end
        end

        context 'with an ID' do
          let(:pending_rel) { build(:pending_relationship_collection_parent, parent_id: parent_record.id) }

          before do
            importer.current_run
            allow(create_relationships_job)
              .to receive(:find_record)
              .and_return([nil, parent_record], [child_entry, child_record])
          end

          it 'calls #collection_parent_work_child' do
            expect(create_relationships_job).to receive(:collection_parent_work_child)

            create_relationships_job.perform(
              parent_identifier: parent_record.id,
              importer_run_id: importer.current_run.id
            )
          end

          it 'calls #add_member_objects on the parent record' do
            expect(parent_record).to receive(:add_member_objects).with([child_record.id])

            create_relationships_job.perform(
              parent_identifier: parent_record.id,
              importer_run_id: importer.current_run.id
            )
          end

          it 'increments the processed relationships counter on the importer run' do
            allow(parent_record).to receive(:add_member_objects)
            create_relationships_job.perform(
              parent_identifier: parent_record.id,
              importer_run_id: importer.current_run.id
            )
            # TODO: current_run.reload doesn't make sense, need to investigate further
            expect(importer.current_run.reload.processed_relationships).to eq(1)
          end
        end
      end

      context 'when adding a child collection to a parent collection' do
        let(:parent_entry) { create(:bulkrax_csv_entry_collection, identifier: 'parent_entry_collection', importerexporter: importer) }
        let(:child_entry) { create(:bulkrax_csv_entry_collection, identifier: 'child_entry_collection', importerexporter: importer) }
        let(:parent_record) { build(:collection) }
        let(:child_record) { build(:another_collection) }
        let(:pending_rel_col) { build(:pending_relationship_collection_child) }
        let(:collection_collection_attrs) do
          {
            parent: parent_record,
            child: child_record
          }
        end

        context 'with a Bulkrax::Entry source_identifier' do
          it 'calls #collection_parent_collection_child' do
            expect(create_relationships_job).to receive(:collection_parent_collection_child)
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_col])

            create_relationships_job.perform(
              parent_identifier: parent_entry.identifier,
              importer_run_id: importer.current_run.id
            )
          end

          it 'runs NestedCollectionPersistenceService' do
            expect(::Hyrax::Collections::NestedCollectionPersistenceService).to receive(:persist_nested_collection_for).with(collection_collection_attrs)
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_col])

            create_relationships_job.perform(
              parent_identifier: parent_entry.identifier,
              importer_run_id: importer.current_run.id
            )
          end

          context 'importer run' do
            it 'increments processed children' do
              allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_col])
              allow(::Hyrax::Collections::NestedCollectionPersistenceService).to receive(:persist_nested_collection_for).with(collection_collection_attrs).and_return(true)
              create_relationships_job.perform(
                parent_identifier: parent_entry.identifier,
                importer_run_id: importer.current_run.id
              )
              expect(importer.current_run.reload.processed_relationships).to eq(1)
            end
          end
        end

        context 'with an ID' do
          let(:pending_rel_col) { build(:pending_relationship_collection_child, parent_id: parent_record.id) }

          before do
            importer.current_run
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_col])
            allow(create_relationships_job)
              .to receive(:find_record)
              .and_return([nil, parent_record], [child_entry, child_record])
          end

          it 'calls #collection_parent_collection_child' do
            expect(create_relationships_job).to receive(:collection_parent_collection_child)

            create_relationships_job.perform(
              parent_identifier: parent_record.id,
              importer_run_id: importer.current_run.id
            )
          end

          it 'runs NestedCollectionPersistenceService' do
            expect(::Hyrax::Collections::NestedCollectionPersistenceService).to receive(:persist_nested_collection_for).with(collection_collection_attrs)

            create_relationships_job.perform(
              parent_identifier: parent_record.id,
              importer_run_id: importer.current_run.id
            )
          end

          context 'importer run' do
            it 'increments processed children' do
              allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_col])
              allow(::Hyrax::Collections::NestedCollectionPersistenceService).to receive(:persist_nested_collection_for).with(collection_collection_attrs).and_return(true)
              create_relationships_job.perform(
                parent_identifier: parent_record.id,
                importer_run_id: importer.current_run.id
              )
              expect(importer.current_run.reload.processed_relationships).to eq(1)
            end
          end
        end
      end

      context 'when adding a child work to a parent work' do
        let(:parent_entry) { create(:bulkrax_csv_entry_work, identifier: 'parent_entry_work', importerexporter: importer) }
        let(:child_entry) { create(:bulkrax_csv_entry_work, identifier: 'child_entry_work', importerexporter: importer) }
        let(:parent_record) { build(:work) }
        let(:child_record) { build(:another_work) }
        let(:env) { Hyrax::Actors::Environment }

        context 'with a Bulkrax::Entry source_identifier' do
          it 'calls #work_parent_work_child' do
            expect(create_relationships_job).to receive(:work_parent_work_child)
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_work])

            create_relationships_job.perform(
                parent_identifier: parent_entry.identifier,
                importer_run_id: importer.current_run.id
              )
          end

          it 'runs CurationConcern' do
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_work])
            allow(Ability).to receive(:new).with(importer.user)
            expect(Hyrax::CurationConcern.actor).to receive(:update).with(instance_of(env))
            create_relationships_job.perform(
              parent_identifier: parent_entry.identifier,
              importer_run_id: importer.current_run.id
            )
          end

          context 'importer run' do
            it 'increments processed children' do
              allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_work])
              allow(Ability).to receive(:new).with(importer.user)
              allow(Hyrax::CurationConcern.actor).to receive(:update).with(instance_of(env)).and_return(true)
              create_relationships_job.perform(
                parent_identifier: parent_entry.identifier,
                importer_run_id: importer.current_run.id
              )
              expect(importer.current_run.reload.processed_relationships).to eq(1)
            end
          end
        end

        context 'with an ID' do
          let(:pending_rel_work) { build(:pending_relationship_collection_child, parent_id: parent_record.id) }

          before do
            importer.current_run
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_work])
            allow(create_relationships_job)
              .to receive(:find_record)
              .and_return([nil, parent_record], [child_entry, child_record])
          end

          it 'calls #work_parent_work_child' do
            expect(create_relationships_job).to receive(:work_parent_work_child)
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_work])

            create_relationships_job.perform(
                parent_identifier: parent_record.id,
                importer_run_id: importer.current_run.id
              )
          end

          it 'runs CurationConcern Actor' do
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_work])
            allow(Ability).to receive(:new).with(importer.user)
            expect(Hyrax::CurationConcern.actor).to receive(:update).with(instance_of(env))
            create_relationships_job.perform(
                parent_identifier: parent_record.id,
                importer_run_id: importer.current_run.id
              )
          end

          context 'importer run' do
            it 'increments processed children' do
              allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_work])
              allow(Ability).to receive(:new).with(importer.user)
              allow(Hyrax::CurationConcern.actor).to receive(:update).with(instance_of(env)).and_return(true)
              create_relationships_job.perform(
                parent_identifier: parent_record.id,
                importer_run_id: importer.current_run.id
              )
              expect(importer.current_run.reload.processed_relationships).to equal(1)
            end
          end
        end
      end

      context 'when adding a child collection to a parent work' do
        let(:parent_entry) { create(:bulkrax_csv_entry_work, importerexporter: importer) }
        let(:child_entry) { create(:bulkrax_csv_entry_collection, importerexporter: importer) }
        let(:parent_record) { build(:work) }
        let(:child_record) { build(:collection) }
        let(:bad_pending_rel) { build(:bad_pending_relationship) }

        it "logs an StandardError to the entry's status" do
          allow(Entry).to receive(:find_by).with(identifier: child_entry.identifier).and_return(child_record)
          allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([bad_pending_rel])

          create_relationships_job.perform(
            parent_identifier: parent_entry.identifier,
            importer_run_id: importer.current_run.id
          )

          expect(parent_entry.latest_status.error_class).to eq("StandardError")
        end

        it 'increments failed children' do
          allow(Entry).to receive(:find_by).with(identifier: child_entry.identifier).and_return(child_record)
          allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([bad_pending_rel])

          create_relationships_job.perform(
            parent_identifier: parent_entry.identifier,
            importer_run_id: importer.current_run.id
          )

          expect(Bulkrax::Importer.find(importer.id).last_run.failed_relationships).to eq(1)
        end
      end

      describe 'rescheduling' do
        context 'when the child record cannot be found' do
          let(:child_record) { nil }

          it 'calls #reschedule' do
            expect(create_relationships_job).to receive(:reschedule)

            create_relationships_job.perform(
              parent_identifier: parent_entry.identifier,
              importer_run_id: importer.current_run.id
            )
          end
        end

        context 'when the parent record cannot be found' do
          let(:parent_record) { nil }

          it 'calls #reschedule' do
            expect(create_relationships_job).to receive(:reschedule)

            create_relationships_job.perform(
              parent_identifier: parent_entry.identifier,
              importer_run_id: importer.current_run.id
            )
          end
        end

        context 'when the child record and parent record can be found' do
          it 'does not call #reschedule' do
            expect(create_relationships_job).not_to receive(:reschedule)
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel])

            create_relationships_job.perform(
              parent_identifier: parent_entry.identifier,
              importer_run_id: importer.current_run.id
            )
          end
        end
      end
    end
  end
end
