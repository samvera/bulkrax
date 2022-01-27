# frozen_string_literal: true

require 'rails_helper'
require Rails.root.parent.parent.join('spec', 'models', 'concerns', 'bulkrax', 'dynamic_record_lookup_spec').to_s

module Bulkrax
  RSpec.describe CreateRelationshipsJob, type: :job do
    subject(:create_relationships_job) { described_class.new }
    let(:importer) { FactoryBot.create(:bulkrax_importer_csv_complex) }
    let(:parent_entry)  { create(:bulkrax_csv_entry_collection, importerexporter: importer) }
    let(:child_entry)   { create(:bulkrax_csv_entry_work, importerexporter: importer) }
    let(:parent_record) { build(:collection) }
    let(:child_record)  { build(:work) }
    let(:parent_factory) { instance_double(ObjectFactory, find: parent_record, run: parent_record) }
    let(:child_factory) { instance_double(ObjectFactory, find: child_record, run: child_record) }
    let(:base_factory_attrs) do
      {
        source_identifier_value: nil,
        work_identifier: :source,
        collection_field_mapping: :collection,
        replace_files: false,
        user: importer.user
      }
    end

    before do
      allow(::Hyrax.config).to receive(:curation_concerns).and_return([Work])
      allow(Entry).to receive(:find_by).with(identifier: child_entry.identifier).and_return(child_entry)
      allow(Entry).to receive(:find_by).with(identifier: parent_entry.identifier).and_return(parent_entry)
      allow(parent_entry).to receive(:factory).and_return(parent_factory)
      allow(child_entry).to receive(:factory).and_return(child_factory)
    end

    describe 'shared examples' do # TODO: remove or rename
      include_examples 'dynamic record lookup'
    end

    describe '#perform' do
      context 'when adding a child work to a parent collection' do
        let(:factory_attrs) do
          base_factory_attrs.merge(
            attributes: {
              id: child_record.id,
              member_of_collections_attributes: { 0 => { id: parent_record.id } }
            },
            klass: child_record.class
          )
        end

        context 'with a Bulkrax::Entry source_identifier' do
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

          context 'importer run' do
            let(:factory) { instance_double(ObjectFactory, run: child_record) }

            before do
              allow(ObjectFactory).to receive(:new).and_return(factory)
            end

            it 'increments processed children' do
              expect(importer.current_run).to receive(:increment!).with(:processed_relationships)

              create_relationships_job.perform(
                entry_identifier: child_entry.identifier,
                parent_identifier: parent_entry.identifier,
                importer_run: importer.current_run
              )
            end
          end
        end

        context 'with an ID' do
          before do
            allow(Entry).to receive(:find_by).with(identifier: parent_record.id).and_return(nil)
            allow(::Collection).to receive(:where).with(id: parent_record.id).and_return([parent_record])
            allow(::Work).to receive(:where).with(id: child_record.id).and_return([child_record])
          end

          it 'calls #collection_parent_work_child' do
            expect(create_relationships_job).to receive(:collection_parent_work_child)

            create_relationships_job.perform(
              entry_identifier: child_entry.identifier,
              parent_identifier: parent_record.id,
              importer_run: importer.current_run
            )
          end

          it 'creates the object factory' do
            expect(ObjectFactory).to receive(:new).with(factory_attrs)

            create_relationships_job.perform(
              entry_identifier: child_entry.identifier,
              parent_identifier: parent_record.id,
              importer_run: importer.current_run
            )
          end

          context 'importer run' do
            before do
              allow(ObjectFactory).to receive(:new).and_return(child_factory)
            end

            it 'increments processed children' do
              expect(importer.current_run).to receive(:increment!).with(:processed_relationships)

              create_relationships_job.perform(
                entry_identifier: child_entry.identifier,
                parent_identifier: parent_record.id,
                importer_run: importer.current_run
              )
            end
          end
        end
      end

      context 'when adding a child collection to a parent collection' do
        let(:parent_entry) { create(:bulkrax_csv_entry_collection, identifier: 'parent_entry_collection', importerexporter: importer) }
        let(:child_entry) { create(:bulkrax_csv_entry_collection, identifier: 'child_entry_collection', importerexporter: importer) }
        let(:parent_record) { build(:collection) }
        let(:child_record) { build(:another_collection) }
        let(:factory_attrs) do
          base_factory_attrs.merge(
            attributes: {
              id: parent_record.id,
              child_collection_id: child_record.id
            },
            klass: parent_record.class
          )
        end

        context 'with a Bulkrax::Entry source_identifier' do
          it 'calls #collection_parent_collection_child' do
            expect(create_relationships_job).to receive(:collection_parent_collection_child)

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

          context 'importer run' do
            let(:factory) { instance_double(ObjectFactory, run: child_record) }

            before do
              allow(ObjectFactory).to receive(:new).and_return(factory)
            end

            it 'increments processed children' do
              expect(importer.current_run).to receive(:increment!).with(:processed_relationships)

              create_relationships_job.perform(
                entry_identifier: child_entry.identifier,
                parent_identifier: parent_entry.identifier,
                importer_run: importer.current_run
              )
            end
          end
        end

        context 'with an ID' do
          before do
            allow(Entry).to receive(:find_by).with(identifier: parent_record.id).and_return(nil)
            allow(::Collection).to receive(:where).with(id: parent_record.id).and_return([parent_record])
            allow(::Work).to receive(:where).with(id: child_record.id).and_return([child_record])
          end

          it 'calls #collection_parent_collection_child' do
            expect(create_relationships_job).to receive(:collection_parent_collection_child)

            create_relationships_job.perform(
              entry_identifier: child_entry.identifier,
              parent_identifier: parent_record.id,
              importer_run: importer.current_run
            )
          end

          it 'creates the object factory' do
            expect(ObjectFactory).to receive(:new).with(factory_attrs)

            create_relationships_job.perform(
              entry_identifier: child_entry.identifier,
              parent_identifier: parent_record.id,
              importer_run: importer.current_run
            )
          end

          context 'importer run' do
            before do
              allow(ObjectFactory).to receive(:new).and_return(child_factory)
            end

            it 'increments processed children' do
              expect(importer.current_run).to receive(:increment!).with(:processed_relationships)

              create_relationships_job.perform(
                entry_identifier: child_entry.identifier,
                parent_identifier: parent_record.id,
                importer_run: importer.current_run
              )
            end
          end
        end
      end

      context 'when adding a child work to a parent work' do
        let(:parent_entry) { create(:bulkrax_csv_entry_work, identifier: 'parent_entry_work', importerexporter: importer) }
        let(:child_entry) { create(:bulkrax_csv_entry_work, identifier: 'child_entry_work', importerexporter: importer) }
        let(:parent_record) { build(:work) }
        let(:child_record) { build(:another_work) }
        let(:factory_attrs) do
          base_factory_attrs.merge(
            attributes: {
              id: parent_record.id,
              work_members_attributes: { 0 => { id: child_record.id } }
            },
            klass: parent_record.class
          )
        end

        context 'with a Bulkrax::Entry source_identifier' do
          it 'calls #work_parent_work_child' do
            expect(create_relationships_job).to receive(:work_parent_work_child)

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

          context 'importer run' do
            let(:factory) { instance_double(ObjectFactory, run: child_record) }

            before do
              allow(ObjectFactory).to receive(:new).and_return(factory)
            end

            it 'increments processed children' do
              expect(importer.current_run).to receive(:increment!).with(:processed_relationships)

              create_relationships_job.perform(
                entry_identifier: child_entry.identifier,
                parent_identifier: parent_entry.identifier,
                importer_run: importer.current_run
              )
            end
          end
        end

        context 'with an ID' do
          before do
            allow(Entry).to receive(:find_by).with(identifier: parent_record.id).and_return(nil)
            allow(::Collection).to receive(:where).with(id: parent_record.id).and_return([parent_record])
            allow(::Work).to receive(:where).with(id: child_record.id).and_return([child_record])
          end

          it 'calls #work_parent_work_child' do
            expect(create_relationships_job).to receive(:work_parent_work_child)

            create_relationships_job.perform(
              entry_identifier: child_entry.identifier,
              parent_identifier: parent_record.id,
              importer_run: importer.current_run
            )
          end

          it 'creates the object factory' do
            expect(ObjectFactory).to receive(:new).with(factory_attrs)

            create_relationships_job.perform(
              entry_identifier: child_entry.identifier,
              parent_identifier: parent_record.id,
              importer_run: importer.current_run
            )
          end

          context 'importer run' do
            before do
              allow(ObjectFactory).to receive(:new).and_return(child_factory)
            end

            it 'increments processed children' do
              expect(importer.current_run).to receive(:increment!).with(:processed_relationships)

              create_relationships_job.perform(
                entry_identifier: child_entry.identifier,
                parent_identifier: parent_record.id,
                importer_run: importer.current_run
              )
            end
          end
        end
      end

      context 'when adding a child collection to a parent work' do
        let(:parent_entry) { create(:bulkrax_csv_entry_work, importerexporter: importer) }
        let(:child_entry) { create(:bulkrax_csv_entry_collection, importerexporter: importer) }
        let(:parent_record) { build(:work) }
        let(:child_record) { build(:collection) }

        it "logs a StandardError to the entry's status" do
          expect(child_entry).to receive(:status_info).with(instance_of(::StandardError))

          create_relationships_job.perform(
            entry_identifier: child_entry.identifier,
            parent_identifier: parent_entry.identifier,
            importer_run: importer.current_run
          )
        end

        it 'increments failed children' do
          expect(importer.current_run).to receive(:increment!).with(:failed_relationships)

          create_relationships_job.perform(
            entry_identifier: child_entry.identifier,
            parent_identifier: parent_entry.identifier,
            importer_run: importer.current_run
          )
        end
      end

      describe 'rescheduling' do
        context 'when the child record cannot be found' do
          let(:child_record) { nil }

          it 'calls #reschedule' do
            expect(create_relationships_job).to receive(:reschedule)

            create_relationships_job.perform(
              entry_identifier: child_entry.identifier,
              parent_identifier: parent_entry.identifier,
              importer_run: importer.current_run
            )
          end
        end

        context 'when the parent record cannot be found' do
          let(:parent_record) { nil }

          it 'calls #reschedule' do
            expect(create_relationships_job).to receive(:reschedule)

            create_relationships_job.perform(
              entry_identifier: child_entry.identifier,
              parent_identifier: parent_entry.identifier,
              importer_run: importer.current_run
            )
          end
        end

        context 'when the child record and parent record can be found' do
          it 'does not call #reschedule' do
            expect(create_relationships_job).not_to receive(:reschedule)

            create_relationships_job.perform(
              entry_identifier: child_entry.identifier,
              parent_identifier: parent_entry.identifier,
              importer_run: importer.current_run
            )
          end
        end
      end
    end
  end
end
