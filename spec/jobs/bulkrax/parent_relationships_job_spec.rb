# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ParentRelationshipsJob, type: :job do
    subject(:parent_relationship_job) { described_class.new }
    let(:importer) { FactoryBot.create(:bulkrax_importer_csv_complex) }
    let(:parent_factory) { instance_double(ObjectFactory, find: parent_record) }
    let(:child_factory) { instance_double(ObjectFactory, find: child_record) }

    before do
      allow(parent_entry).to receive(:factory).and_return(parent_factory)
      allow(child_entry).to receive(:factory).and_return(child_factory)
    end

    describe '#add_parent_relationships' do
      before do
        allow(Entry).to receive(:find).with(child_entry.id).and_return(child_entry)
        allow(Entry).to receive(:find_by).with(identifier: parent_entry.identifier).and_return(parent_entry)
      end

      context 'when adding a child work to a parent collection' do
        let(:parent_entry) { create(:bulkrax_csv_entry_collection, importerexporter: importer) }
        let(:child_entry) { create(:bulkrax_csv_entry_work, importerexporter: importer) }
        let(:parent_record) { build(:collection) }
        let(:child_record) { build(:work) }

        it 'calls #collection_parent_work_child' do
          expect(parent_relationship_job)
            .to receive(:collection_parent_work_child)
            .with(parent_id: parent_record.id, child_id: child_record.id)

          parent_relationship_job.perform(child_entry.id, [parent_entry.identifier], importer.current_run.id)
        end
      end

      context 'when adding a child collection to a parent collection' do
        let(:parent_entry) { create(:bulkrax_csv_entry_collection, identifier: 'parent_entry_collection', importerexporter: importer) }
        let(:child_entry) { create(:bulkrax_csv_entry_collection, identifier: 'child_entry_collection', importerexporter: importer) }
        let(:parent_record) { build(:collection) }
        let(:child_record) { build(:another_collection) }

        it 'calls #collection_parent_collection_child' do
          expect(parent_relationship_job)
            .to receive(:collection_parent_collection_child)
            .with(parent_id: parent_record.id, child_ids: [child_record.id])

          parent_relationship_job.perform(child_entry.id, [parent_entry.identifier], importer.current_run.id)
        end
      end

      context 'when adding a child work to a parent work' do
        let(:parent_entry) { create(:bulkrax_csv_entry_work, identifier: 'parent_entry_work', importerexporter: importer) }
        let(:child_entry) { create(:bulkrax_csv_entry_work, identifier: 'child_entry_work', importerexporter: importer) }
        let(:parent_record) { build(:work) }
        let(:child_record) { build(:another_work) }

        it 'calls #work_parent_work_child' do
          expect(parent_relationship_job)
            .to receive(:work_parent_work_child)
            .with(parent_id: parent_record.id, child_ids: [child_record.id])

          parent_relationship_job.perform(child_entry.id, [parent_entry.identifier], importer.current_run.id)
        end
      end

      context 'when adding a child collection to a parent work' do
        let(:parent_entry) { create(:bulkrax_csv_entry_work, importerexporter: importer) }
        let(:child_entry) { create(:bulkrax_csv_entry_collection, importerexporter: importer) }
        let(:parent_record) { build(:work) }
        let(:child_record) { build(:collection) }

        it 'raises a StandardError' do
          expect { parent_relationship_job.perform(child_entry.id, [parent_entry.identifier], importer.current_run.id) }
            .to raise_error(::StandardError, 'a Collection may not be assigned as a child of a Work')
        end
      end
    end
  end
end
