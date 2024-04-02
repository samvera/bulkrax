# frozen_string_literal: true

require 'rails_helper'

# Dear maintainer and code reader.  This spec stubs and mocks far too many
# things to be immediately effective.  Why?  Because we don't have a functional
# test object factory and data model.
#
# Because of this and a significant refactor of the object model; namely that we
# moved to a repository pattern where we tell the repository to perform the
# various commands instead of commands directly on the object.  This moved to a
# repository pattern is necessitated by the shift from Hyrax's ActiveFedora
# usage to Hyrax's Valkyrie uses.
module Bulkrax
  RSpec.describe CreateRelationshipsJob, type: :job do
    let(:create_relationships_job) { described_class.new }
    let(:importer) { FactoryBot.create(:bulkrax_importer_csv_complex) }
    let(:parent_entry) { create(:bulkrax_csv_entry_collection, importerexporter: importer) }
    let(:child_entry) { create(:bulkrax_csv_entry_work, importerexporter: importer) }
    let(:parent_record) { build(:collection) }
    let(:child_record) { build(:work) }
    let(:pending_rel) { create(:pending_relationship_collection_parent, importer_run: importer.current_run, parent_id: parent_id, child_id: child_id) }
    let(:pending_rel_work) { build(:pending_relationship_work_parent) }
    let(:parent_id) { parent_entry.identifier }
    let(:child_id) { child_entry.identifier }

    around do |spec|
      old = Bulkrax.object_factory
      Bulkrax.object_factory = Bulkrax::MockObjectFactory
      spec.run
      Bulkrax.object_factory = old
    end
    before do
      allow_any_instance_of(Ability).to receive(:authorize!).and_return(true)

      allow(create_relationships_job).to receive(:reschedule)
      allow(::Hyrax.config).to receive(:curation_concerns).and_return([Work])
      allow(Bulkrax::MockObjectFactory).to receive(:save!).and_return(true)
      allow(child_record).to receive(:update_index)
      allow(child_record).to receive(:member_of_collections).and_return([])
      allow(parent_record).to receive(:ordered_members).and_return([])

      allow(create_relationships_job).to receive(:find_record)
      allow(create_relationships_job).to receive(:find_record).with(parent_id, importer.current_run.id).and_return([parent_entry, parent_record])
      allow(create_relationships_job).to receive(:find_record).with(child_id, importer.current_run.id).and_return([child_entry, child_record])

      pending_rel
    end

    describe 'is capable of looking up records dynamically' do
      include_examples 'dynamic record lookup'
    end

    describe '#perform' do
      subject(:perform) do
        create_relationships_job.perform(
          parent_identifier: parent_id, # source_identifier
          importer_run_id: importer.current_run.id
        )
      end

      xcontext 'when adding a child work to a parent collection' do
        before { allow(child_record).to receive(:file_sets).and_return([]) }

        it 'assigns the parent to the child\'s #member_of_collections' do
          expect { perform }.to change(child_record, :member_of_collections).from([]).to([parent_record])
        end

        it 'increments the processed relationships counter on the importer run' do
          expect { perform }.to change { importer.current_run.reload.processed_relationships }.by(1)
        end

        it 'deletes the pending relationship' do
          expect { perform }.to change(Bulkrax::PendingRelationship, :count).by(-1)
        end

        it 'does not reschedule the job' do
          perform
          expect(create_relationships_job).not_to have_received(:reschedule)
        end
      end

      xcontext 'when adding a child collection to a parent collection' do
        let(:child_record) { build(:another_collection) }
        let(:child_entry) { create(:bulkrax_csv_another_entry_collection, importerexporter: importer) }

        it 'assigns the parent to the child\'s #member_of_collections' do
          expect { perform }.to change(child_record, :member_of_collections).from([]).to([parent_record])
        end

        it 'increments the processed relationships counter on the importer run' do
          expect { perform }.to change { importer.current_run.reload.processed_relationships }.by(1)
        end

        it 'deletes the pending relationship' do
          expect { perform }.to change(Bulkrax::PendingRelationship, :count).by(-1)
        end

        it 'does not reschedule the job' do
          perform
          expect(create_relationships_job).not_to have_received(:reschedule)
        end

        # TODO: Do we need to account for this because of Hyrax 2.9.x implementations?
        xit 'runs NestedCollectionPersistenceService'
      end

      xcontext 'when adding a child work to a parent work' do
        let(:parent_record) { build(:another_work) }
        let(:parent_entry) { create(:bulkrax_csv_entry_work, identifier: "other_identifier", importerexporter: importer) }

        it 'assigns the child to the parent\'s #ordered_members' do
          expect { perform }.to change(parent_record, :ordered_members).from([]).to([child_record])
        end

        it 'reindexes the child work' do
          perform
          expect(child_record).to have_received(:update_index)
        end

        it 'increments the processed relationships counter on the importer run' do
          expect { perform }.to change { importer.current_run.reload.processed_relationships }.by(1)
        end

        it 'deletes the pending relationship' do
          expect { perform }.to change(Bulkrax::PendingRelationship, :count).by(-1)
        end
      end

      xcontext 'when adding a child collection to a parent work' do
        let(:child_entry) { create(:bulkrax_csv_entry_collection, importerexporter: importer) }
        let(:parent_entry) { create(:bulkrax_csv_entry_work, importerexporter: importer) }
        let(:child_record) { build(:collection) }
        let(:parent_record) { build(:work) }

        it 'logs an error to the parent entry' do
          expect { perform }.to change(parent_entry, :failed?).to(true)
        end

        it 'increments current importer run\'s :failed_relationships' do
          expect { perform }.to change { importer.current_run.reload.failed_relationships }.by(1)
        end
      end

      xcontext 'when adding a child record that is not found' do
        it 'reschudules the job' do
          expect(create_relationships_job).to receive(:find_record).with(child_id, importer.current_run.id).and_return([nil, nil])
          perform
          expect(create_relationships_job).to have_received(:reschedule).with(parent_identifier: parent_id, importer_run_id: importer.current_run.id)
        end
      end

      xcontext 'when adding a parent record that is not found' do
        it 'reschedules the job' do
          expect(create_relationships_job).to receive(:find_record).with(parent_id, importer.current_run.id).and_return([nil, nil])
          perform
          expect(create_relationships_job).to have_received(:reschedule).with(parent_identifier: parent_id, importer_run_id: importer.current_run.id)
        end
      end
    end
  end
end
