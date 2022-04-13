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
    let(:pending_rel)   { build(:pending_relationship_collection_parent) }
    let(:pending_rel_work)   { build(:pending_relationship_work_parent) }
    let(:base_factory_attrs) do
      {
        source_identifier_value: nil,
        work_identifier: :source,
        related_parents_parsed_mapping: parent_entry.parser.related_parents_parsed_mapping,
        replace_files: false,
        user: importer.user
      }
    end

    before do
      allow(::Hyrax.config).to receive(:curation_concerns).and_return([Work])
      allow(Entry).to receive(:find_by).with(identifier: child_entry.identifier, importerexporter_id: importer.id).and_return(child_entry)
      allow(Entry).to receive(:find_by).with(identifier: parent_entry.identifier, importerexporter_id: importer.id).and_return(parent_entry)
      allow(parent_entry).to receive(:factory).and_return(parent_factory)
      allow(child_entry).to receive(:factory).and_return(child_factory)
    end

    describe 'is capable of looking up records dynamically' do
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
            klass: child_record.class,
            importer_run_id: importer.current_run.id
          )
        end

        context 'with a Bulkrax::Entry source_identifier' do
          it 'calls #collection_parent_work_child' do
            expect(create_relationships_job).to receive(:collection_parent_work_child)
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel])
            create_relationships_job.perform(
              parent_identifier: parent_entry.identifier, # source_identifier
              importer_run_id: importer.current_run.id
            )
          end

          it 'creates and runs the object factory' do
            expect(ObjectFactory).to receive(:new).with(factory_attrs).and_return(parent_factory)
            expect(parent_factory).to receive(:run)
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel])

            create_relationships_job.perform(
              parent_identifier: parent_entry.identifier,
              importer_run_id: importer.current_run.id
            )
          end

          context 'importer run' do
            let(:factory) { instance_double(ObjectFactory, run: child_record) }

            before do
              allow(ObjectFactory).to receive(:new).and_return(factory)
              allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel])
            end

            it 'increments processed relationships' do
              create_relationships_job.perform(
                parent_identifier: parent_entry.identifier,
                importer_run_id: importer.current_run.id
              )

              expect(importer.last_run.processed_relationships).to equal(1)
              # create_relationships_job.perform(
              #   entry_identifier: child_entry.identifier,
              #   parent_identifier: parent_entry.identifier,
              #   importer_run: importer.current_run
              # )
            end
          end
        end

        context 'with an ID' do
          before do
            allow(Entry).to receive(:find_by).with(identifier: parent_record.id).and_return(nil)
            allow(::Collection).to receive(:where).with(id: parent_record.id).and_return([parent_record])
            allow(::Work).to receive(:where).with(id: child_record.id).and_return([child_record])
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel])
          end

          it 'calls #collection_parent_work_child' do
            expect(create_relationships_job).to receive(:collection_parent_work_child)

            create_relationships_job.perform(
              parent_identifier: parent_entry.identifier,
              importer_run_id: importer.current_run.id
            )
          end

          it 'creates the object factory' do
            expect(ObjectFactory).to receive(:new).with(factory_attrs).and_return(child_factory)

            create_relationships_job.perform(
              parent_identifier: parent_entry.identifier,
              importer_run_id: importer.current_run.id
            )
          end

          context 'importer run' do
            before do
              allow(ObjectFactory).to receive(:new).and_return(child_factory)
              allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel])
            end

            it 'increments processed relationships' do
              create_relationships_job.perform(
                parent_identifier: parent_entry.identifier,
                importer_run_id: importer.current_run.id
              )

              expect(importer.last_run.processed_relationships).to equal(1)
            end
          end
        end
      end

      context 'when adding a child collection to a parent collection' do
        let(:parent_entry) { create(:bulkrax_csv_entry_collection, identifier: 'parent_entry_collection', importerexporter: importer) }
        let(:child_entry) { create(:bulkrax_csv_entry_collection, identifier: 'child_entry_collection', importerexporter: importer) }
        let(:parent_record) { build(:collection) }
        let(:child_record) { build(:another_collection) }
        let(:pending_rel_col) { build(:pending_relationship_collection_child) }
        let(:factory_attrs) do
          base_factory_attrs.merge(
            attributes: {
              id: parent_record.id,
              child_collection_id: child_record.id
            },
            klass: parent_record.class,
            importer_run_id: importer.current_run.id
          )
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

          it 'creates the object factory' do
            expect(ObjectFactory).to receive(:new).with(factory_attrs).and_return(child_factory)
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_col])

            create_relationships_job.perform(
              parent_identifier: parent_entry.identifier,
              importer_run_id: importer.current_run.id
            )
          end

          context 'importer run' do
            let(:factory) { instance_double(ObjectFactory, run: child_record) }

            before do
              allow(ObjectFactory).to receive(:new).and_return(factory)
            end

            it 'increments processed children' do
              allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_col])

              create_relationships_job.perform(
                parent_identifier: parent_entry.identifier,
                importer_run_id: importer.current_run.id
              )

              expect(importer.last_run.processed_relationships).to equal(1)
            end
          end
        end

        context 'with an ID' do
          before do
            allow(Entry).to receive(:find_by).with(identifier: parent_record.id).and_return(nil)
            allow(::Collection).to receive(:where).with(id: parent_record.id).and_return([parent_record])
            allow(::Work).to receive(:where).with(id: child_record.id).and_return([child_record])
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_col])
          end

          it 'calls #collection_parent_collection_child' do
            expect(create_relationships_job).to receive(:collection_parent_collection_child)

            create_relationships_job.perform(
              parent_identifier: parent_entry.identifier,
              importer_run_id: importer.current_run.id
            )
          end

          it 'creates the object factory' do
            expect(ObjectFactory).to receive(:new).with(factory_attrs).and_return(child_factory)

            create_relationships_job.perform(
              parent_identifier: parent_entry.identifier,
              importer_run_id: importer.current_run.id
            )
          end

          context 'importer run' do
            before do
              allow(ObjectFactory).to receive(:new).and_return(parent_factory)
            end

            it 'increments processed children' do
              create_relationships_job.perform(
                parent_identifier: parent_entry.identifier,
                importer_run_id: importer.current_run.id
              )

              expect(importer.last_run.processed_relationships).to equal(1)
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
            klass: parent_record.class,
            importer_run_id: importer.current_run.id
          )
        end

        context 'with a Bulkrax::Entry source_identifier' do
          it 'calls #work_parent_work_child' do
            expect(create_relationships_job).to receive(:work_parent_work_child)
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_work])

            create_relationships_job.perform(
                parent_identifier: parent_entry.identifier,
                importer_run_id: importer.current_run.id
              )
          end

          it 'creates the object factory' do
            expect(ObjectFactory).to receive(:new).with(factory_attrs).and_return(parent_factory)
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_work])

            create_relationships_job.perform(
                parent_identifier: parent_entry.identifier,
                importer_run_id: importer.current_run.id
              )
          end

          context 'importer run' do
            let(:factory) { instance_double(ObjectFactory, run: child_record) }

            before do
              allow(ObjectFactory).to receive(:new).and_return(factory)
              allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_work])
            end

            it 'increments processed children' do
              create_relationships_job.perform(
                parent_identifier: parent_entry.identifier,
                importer_run_id: importer.current_run.id
              )

              expect(importer.last_run.processed_relationships).to equal(1)
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
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_work])

            create_relationships_job.perform(
                parent_identifier: parent_entry.identifier,
                importer_run_id: importer.current_run.id
              )
          end

          it 'creates the object factory' do
            expect(ObjectFactory).to receive(:new).with(factory_attrs).and_return(parent_factory)
            allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_work])

            create_relationships_job.perform(
                parent_identifier: parent_entry.identifier,
                importer_run_id: importer.current_run.id
              )
          end

          context 'importer run' do
            before do
              allow(ObjectFactory).to receive(:new).and_return(child_factory)
              allow(Bulkrax::PendingRelationship).to receive(:find_each).and_return([pending_rel_work])
            end

            it 'increments processed children' do
              create_relationships_job.perform(
                parent_identifier: parent_entry.identifier,
                importer_run_id: importer.current_run.id
              )

              expect(importer.last_run.processed_relationships).to equal(1)
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
