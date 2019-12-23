# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ChildRelationshipsJob, type: :job do
    let(:importer) { FactoryBot.build(:bulkrax_importer_csv_complex) }
    let(:entry_work) { FactoryBot.build(:bulkrax_csv_entry_work, importerexporter: importer) }
    let(:child_entry) { FactoryBot.build(:bulkrax_csv_entry, importerexporter: importer) }
    let(:entry_collection) { FactoryBot.create(:bulkrax_csv_entry_collection, importerexporter: importer) }
    let(:work_parent) { FactoryBot.build(:work) }
    let(:work_child) { FactoryBot.build(:another_work) }
    let(:collection_parent) { FactoryBot.build(:collection) }
    let(:collection_child) { FactoryBot.build(:collection) }
    let(:factory) { double(Bulkrax::ObjectFactory) }

    before do
      allow(entry_work).to receive(:factory_class).and_return(Work)
      allow(entry_work).to receive_message_chain(:factory, :find).and_return(work_parent)
      allow(entry_collection).to receive(:factory_class).and_return(Collection)
      allow(entry_collection).to receive_message_chain(:factory, :find).and_return(collection_parent)
      allow(Bulkrax::ImporterRun).to receive(:find).with(3).and_return(importer.current_importer_run)
      allow(factory).to receive(:run)
    end

    describe '#work-parent-work-child' do
      before do
        allow(Bulkrax::Entry).to receive(:find).with(1).and_return(entry_work)
        allow(Bulkrax::Entry).to receive(:find).with(2).and_return(child_entry)
        allow(child_entry).to receive(:factory_class).and_return(Work)
        allow(child_entry).to receive_message_chain(:factory, :find).and_return(work_child)
      end

      it 'calls work_parent_work_child' do
        expect(subject).to receive(:work_parent_work_child).with([work_child.id])
        subject.perform(1, [2], 3)
      end

      it 'creates the object factory' do
        expect(Bulkrax::ObjectFactory).to receive(:new).with(
          { id: "work_id", work_members_attributes: { 0 => { id: "another_work_id" } } },
          'entry_work',
          false,
          importer.user,
          Work
        )
        subject.perform(1, [2], 3)
      end

      context 'importer run' do
        before do
          allow(Bulkrax::ObjectFactory).to receive(:new).and_return(factory)
        end

        it 'increments processed children' do
          expect(importer.current_importer_run).to receive(:increment!).with(:processed_children)
          subject.perform(1, [2], 3)
        end
      end

      context 'skips child collection of works' do
        before do
          allow(Bulkrax::ObjectFactory).to receive(:new).and_return(factory)
          allow(Bulkrax::Entry).to receive(:find).with(1).and_return(entry_work)
          allow(Bulkrax::Entry).to receive(:find).with(2).and_return(child_entry)
          allow(child_entry).to receive(:factory_class).and_return(Collection)
          allow(child_entry).to receive_message_chain(:factory, :find).and_return(collection_child)
        end

        it 'does not increment processed or failed children' do
          expect(importer.current_importer_run).not_to receive(:increment!).with(:processed_children)
          expect(importer.current_importer_run).not_to receive(:increment!).with(:failed_children)
          subject.perform(1, [2], 3)
        end
      end
    end

    describe '#work_child_collection_parent' do
      before do
        allow(Bulkrax::Entry).to receive(:find).with(1).and_return(entry_collection)
        allow(Bulkrax::Entry).to receive(:find).with(2).and_return(child_entry)
        allow(child_entry).to receive(:factory_class).and_return(Work)
        allow(child_entry).to receive_message_chain(:factory, :find).and_return(work_child)
      end

      it 'calls work_child_collection_parent' do
        expect(subject).to receive(:work_child_collection_parent).with(work_child.id)
        subject.perform(1, [2], 3)
      end

      it 'creates the object factory' do
        expect(Bulkrax::ObjectFactory).to receive(:new).with(
          { collections: [{ id: "collection_id" }], id: "another_work_id" },
          'csv_entry',
          false,
          importer.user,
          Work
        )
        subject.perform(1, [2], 3)
      end

      context 'importer runs' do
        before do
          allow(Bulkrax::ObjectFactory).to receive(:new).and_return(factory)
        end

        it 'increments processed children' do
          expect(importer.current_importer_run).to receive(:increment!).with(:processed_children)
          subject.perform(1, [2], 3)
        end
      end
    end

    describe 'collection_parent_collection_child' do
      before do
        allow(Bulkrax::Entry).to receive(:find).with(1).and_return(entry_collection)
        allow(Bulkrax::Entry).to receive(:find).with(2).and_return(child_entry)
        allow(child_entry).to receive(:factory_class).and_return(Collection)
        allow(child_entry).to receive_message_chain(:factory, :find).and_return(collection_child)
      end

      it 'calls collection_parent_collection_child' do
        expect(subject).to receive(:collection_parent_collection_child).with([collection_child.id])
        subject.perform(1, [2], 3)
      end

      it 'creates the object factory' do
        expect(Bulkrax::ObjectFactory).to receive(:new).with(
          { children: ["collection_id"], id: "collection_id" },
          'entry_collection',
          false,
          importer.user,
          Collection
        )
        subject.perform(1, [2], 3)
      end

      context 'importer runs' do
        before do
          allow(Bulkrax::ObjectFactory).to receive(:new).and_return(factory)
        end

        it 'increments processed children' do
          expect(importer.current_importer_run).to receive(:increment!).with(:processed_children)
          subject.perform(1, [2], 3)
        end
      end
    end

    describe 'error handling' do
      context 'error outside adding relationships' do
        before do
          allow(subject).to receive(:build_child_works_hash).and_raise(StandardError)
        end
        it 'does not increment failed children' do
          expect { subject.perform(1, [2], 3) } .to raise_error(StandardError)
          expect(importer.current_importer_run).not_to receive(:increment!).with(:failed_children)
        end
      end

      context 'error in adding relationships' do
        # this will error because we haven't stubbed the factory
        before do
          allow(Bulkrax::Entry).to receive(:find).with(1).and_return(entry_work)
          allow(Bulkrax::Entry).to receive(:find).with(2).and_return(child_entry)
          allow(child_entry).to receive(:factory_class).and_return(Work)
          allow(child_entry).to receive_message_chain(:factory, :find).and_return(work_child)
        end
        it 'increments failed children' do
          expect(importer.current_importer_run).to receive(:increment!).with(:failed_children)
          subject.perform(1, [2], 3)
        end
      end

      context 'reschedule' do
        before do
          allow(subject).to receive(:build_child_works_hash).and_raise(Bulkrax::ChildWorksError)
        end
        it 'does not increment failed children' do
          expect(subject).to receive(:reschedule).with(1, [2], 3)
          subject.perform(1, [2], 3)
        end
      end
    end
  end
end
