# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe CreateRelationshipsJob, type: :job do
    subject(:create_relationships_job) { described_class.new }
    let(:importer) { FactoryBot.create(:bulkrax_importer_csv_complex) }
    let(:parent_factory) { instance_double(ObjectFactory, find: parent_record) }
    let(:child_factory) { instance_double(ObjectFactory, find: child_record) }

    before do
      allow(::Hyrax.config).to receive(:curation_concerns).and_return([Work])
      allow(parent_entry).to receive(:factory).and_return(parent_factory)
      allow(child_entry).to receive(:factory).and_return(child_factory)
    end

    describe '#perform' do
      before do
        allow(Entry).to receive(:find_by).with(identifier: child_entry.identifier).and_return(child_entry)
        allow(Entry).to receive(:find_by).with(identifier: parent_entry.identifier).and_return(parent_entry)
      end

      context 'when adding a child work to a parent collection' do
        let(:parent_entry)  { create(:bulkrax_csv_entry_collection, importerexporter: importer) }
        let(:child_entry)   { create(:bulkrax_csv_entry_work, importerexporter: importer) }
        let(:parent_record) { build(:collection) }
        let(:child_record)  { build(:work) }
        let(:factory_attrs) do
          {
            attributes: {
              id: child_record.id,
              member_of_collections_attributes: { 0 => { id: parent_record.id } }
            },
            source_identifier_value: nil,
            work_identifier: :source,
            collection_field_mapping: :collection,
            replace_files: false,
            user: importer.user,
            klass: child_record.class
          }
        end

        it 'calls #collection_parent_work_child' do
          expect(create_relationships_job).to receive(:collection_parent_work_child)

          create_relationships_job.perform(
            entry_identifier: child_entry.identifier,
            parent_identifier: parent_entry.identifier,
            importer_run: importer.current_run
          )
        end

        it 'creates the object factory' do
          expect(ObjectFactory).to receive(:new).with(factory_attrs)

          create_relationships_job.perform(
            entry_identifier: child_entry.identifier,
            parent_identifier: parent_entry.identifier,
            importer_run: importer.current_run
          )
        end
      end

      context 'when adding a child collection to a parent collection' do
        let(:parent_entry) { create(:bulkrax_csv_entry_collection, identifier: 'parent_entry_collection', importerexporter: importer) }
        let(:child_entry) { create(:bulkrax_csv_entry_collection, identifier: 'child_entry_collection', importerexporter: importer) }
        let(:parent_record) { build(:collection) }
        let(:child_record) { build(:another_collection) }

        it 'calls #collection_parent_collection_child' do
          expect(create_relationships_job).to receive(:collection_parent_collection_child)

          create_relationships_job.perform(
            entry_identifier: child_entry.identifier,
            parent_identifier: parent_entry.identifier,
            importer_run: importer.current_run
          )
        end
      end

      context 'when adding a child work to a parent work' do
        let(:parent_entry) { create(:bulkrax_csv_entry_work, identifier: 'parent_entry_work', importerexporter: importer) }
        let(:child_entry) { create(:bulkrax_csv_entry_work, identifier: 'child_entry_work', importerexporter: importer) }
        let(:parent_record) { build(:work) }
        let(:child_record) { build(:another_work) }

        it 'calls #work_parent_work_child' do
          expect(create_relationships_job).to receive(:work_parent_work_child)

          create_relationships_job.perform(
            entry_identifier: child_entry.identifier,
            parent_identifier: parent_entry.identifier,
            importer_run: importer.current_run
          )
        end
      end

      context 'when adding a child collection to a parent work' do
        let(:parent_entry) { create(:bulkrax_csv_entry_work, importerexporter: importer) }
        let(:child_entry) { create(:bulkrax_csv_entry_collection, importerexporter: importer) }
        let(:parent_record) { build(:work) }
        let(:child_record) { build(:collection) }

        it 'raises a StandardError' do
          expect do
            create_relationships_job.perform(
              entry_identifier: child_entry.identifier,
              parent_identifier: parent_entry.identifier,
              importer_run: importer.current_run
            )
          end.to raise_error(::StandardError, 'a Collection may not be assigned as a child of a Work')
        end
      end
    end
  end
end
