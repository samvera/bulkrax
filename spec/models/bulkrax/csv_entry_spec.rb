# frozen_string_literal: true
# rubocop: disable Metrics/BlockLength

require 'rails_helper'

module Bulkrax
  RSpec.describe CsvEntry, type: :model do
    let(:collection) { FactoryBot.build(:collection) }
    let(:hyrax_record) do
      OpenStruct.new(
        file_sets: [],
        member_of_collections: [],
        member_of_work_ids: [],
        in_work_ids: [],
        member_work_ids: []
      )
    end

    before do
      allow_any_instance_of(described_class).to receive(:collections_created?).and_return(true)
      allow_any_instance_of(described_class).to receive(:find_collection).and_return(collection)
      allow(subject).to receive(:hyrax_record).and_return(hyrax_record)
    end

    describe 'builds entry' do
      subject { described_class.new(importerexporter: importer) }
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }

      context 'without required metadata' do
        before do
          allow(subject).to receive(:raw_metadata).and_return(source_identifier: '1', some_field: 'some data')
        end

        it 'fails and stores an error' do
          expect { subject.build_metadata }.to raise_error(StandardError)
        end
      end

      context 'with required metadata' do
        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:raw_metadata).and_return('source_identifier' => '2', 'title' => 'some title')
        end

        it 'succeeds' do
          subject.build
          expect(subject.status).to eq('Complete')
          expect(subject.parsed_metadata['admin_set_id']).to eq 'MyString'
        end

        it 'has a source id field' do
          expect(subject.source_identifier).to eq('source_identifier')
        end

        it 'has a work id field' do
          expect(subject.work_identifier).to eq('source')
        end

        it 'has custom source and work id fields' do
          subject.importerexporter.field_mapping['title'] = { 'from' => ['title'], 'source_identifier' => true }
          expect(subject.source_identifier).to eq('title')
          expect(subject.work_identifier).to eq('title')
        end
      end

      context 'with parent-child relationships' do
        let(:importer) { FactoryBot.create(:bulkrax_importer_csv, :with_relationships_mappings) }
        let(:required_data) do
          {
            'source_identifier' => '1',
            'title' => 'test'
          }
        end

        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:raw_metadata).and_return(data)
        end

        context 'with multiple values split by a pipe character' do
          let(:data) do
            required_data.merge(
              {
                'parents_column' => 'parent_1 | parent_2',
                'children_column' => 'child_1|child_2'
              }
            )
          end

          it 'succeeds' do
            metadata = subject.build_metadata
            expect(metadata['parents']).to include('parent_1', 'parent_2')
            expect(metadata['children']).to include('child_1', 'child_2')
          end
        end

        context 'with enumerated columns appended' do
          let(:data) do
            required_data.merge(
              {
                'parents_column_1' => 'parent_1',
                'parents_column_2' => 'parent_2',
                'children_column_1' => 'child_1',
                'children_column_2' => 'child_2'
              }
            )
          end

          it 'succeeds' do
            metadata = subject.build_metadata
            expect(metadata['parents']).to include('parent_1', 'parent_2')
            expect(metadata['children']).to include('child_1', 'child_2')
          end
        end

        context 'with enumerated columns prepended' do
          let(:data) do
            required_data.merge(
              {
                '1_parents_column' => 'parent_1',
                '2_parents_column' => 'parent_2',
                '1_children_column' => 'child_1',
                '2_children_column' => 'child_2'
              }
            )
          end

          it 'succeeds' do
            metadata = subject.build_metadata
            expect(metadata['parents']).to include('parent_1', 'parent_2')
            expect(metadata['children']).to include('child_1', 'child_2')
          end
        end
      end

      context 'with enumerated columns appended' do
        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:raw_metadata).and_return('source_identifier' => '2', 'title_1' => 'some title', 'title_2' => 'another title')
        end

        it 'succeeds' do
          metadata = subject.build_metadata
          expect(metadata['title']).to include('some title')
          expect(metadata['title']).to include('another title')
        end
      end

      context 'with enumerated columns prepended' do
        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:raw_metadata).and_return('source_identifier' => '2', '1_title' => 'some title', '2_title' => 'another title')
        end

        it 'succeeds' do
          metadata = subject.build_metadata
          expect(metadata['title']).to include('some title')
          expect(metadata['title']).to include('another title')
        end
      end

      context 'with files containing spaces' do
        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)

          allow(subject).to receive(:raw_metadata).and_return('source_identifier' => '3', 'title' => 'some title')
          allow(File).to receive(:exist?).with('./spec/fixtures/csv/test_file.csv').and_return(true)
        end

        it 'sets up the file_path and removes spaces from filenames' do
          subject.build
          expect(subject.status).to eq('Complete')
        end
      end

      context 'with object fields prefixed' do
        let(:importer) do
          FactoryBot.create(:bulkrax_importer_csv, field_mapping: {
                              'single_object_first_name' => { from: ['single_object_first_name'], object: 'single_object' },
                              'single_object_last_name' => { from: ['single_object_last_name'], object: 'single_object' },
                              'single_object_position' => { from: ['single_object_position'], object: 'single_object' },
                              'single_object_language' => { from: ['single_object_language'], object: 'single_object', parsed: true }
                            })
        end

        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:raw_metadata).and_return(
            'source_identifier' => '2',
            'title' => 'some title',
            'single_object_first_name' => 'Fake',
            'single_object_last_name' => 'Fakerson',
            'single_object_position' => 'Leader, Jester, Queen',
            'single_object_language' => 'english'
          )
        end

        it 'succeeds' do
          metadata = subject.build_metadata
          expect(metadata['single_object']['single_object_first_name']).to eq('Fake')
          expect(metadata['single_object']['single_object_last_name']).to eq('Fakerson')
          expect(metadata['single_object']['single_object_position']).to include('Leader', 'Jester', 'Queen')
          expect(metadata['single_object']['single_object_language']).to eq('English')
        end
      end

      context 'with object fields and no prefix' do
        let(:importer) do
          FactoryBot.create(:bulkrax_importer_csv, field_mapping: {
                              'first_name' => { from: ['single_object_first_name'], object: 'single_object' },
                              'last_name' => { from: ['single_object_last_name'], object: 'single_object' },
                              'position' => { from: ['single_object_position'], object: 'single_object' },
                              'language' => { from: ['single_object_language'], object: 'single_object', parsed: true }
                            })
        end

        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:raw_metadata).and_return(
            'source_identifier' => '2',
            'title' => 'some title',
            'single_object_first_name' => 'Fake',
            'single_object_last_name' => 'Fakerson',
            'single_object_position' => 'Leader, Jester, Queen',
            'single_object_language' => 'english'
          )
        end

        it 'succeeds' do
          metadata = subject.build_metadata
          expect(metadata['single_object']['first_name']).to eq('Fake')
          expect(metadata['single_object']['last_name']).to eq('Fakerson')
          expect(metadata['single_object']['position']).to include('Leader', 'Jester', 'Queen')
          expect(metadata['single_object']['language']).to eq('English')
        end
      end

      context 'with multiple objects and fields prefixed' do
        let(:importer) do
          FactoryBot.create(:bulkrax_importer_csv, field_mapping: {
                              'multiple_objects_first_name' => { from: ['multiple_objects_first_name'], object: 'multiple_objects' },
                              'multiple_objects_last_name' => { from: ['multiple_objects_last_name'], object: 'multiple_objects' },
                              'multiple_objects_position' => { from: ['multiple_objects_position'], object: 'multiple_objects' },
                              'multiple_objects_language' => { from: ['multiple_objects_language'], object: 'multiple_objects', parsed: true }
                            })
        end

        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:raw_metadata).and_return(
            'source_identifier' => '2',
            'title' => 'some title',
            'multiple_objects_first_name_1' => 'Fake',
            'multiple_objects_last_name_1' => 'Fakerson',
            'multiple_objects_position_1' => 'Leader, Jester, Queen',
            'multiple_objects_language_1' => 'english',
            'multiple_objects_first_name_2' => 'Judge',
            'multiple_objects_last_name_2' => 'Hines',
            'multiple_objects_position_2' => 'King, Lord, Duke'
          )
        end

        it 'succeeds' do
          metadata = subject.build_metadata
          expect(metadata['multiple_objects'][0]['multiple_objects_first_name']).to eq('Fake')
          expect(metadata['multiple_objects'][0]['multiple_objects_last_name']).to eq('Fakerson')
          expect(metadata['multiple_objects'][0]['multiple_objects_position']).to include('Leader', 'Jester', 'Queen')
          expect(metadata['multiple_objects'][0]['multiple_objects_language']).to eq('English')
          expect(metadata['multiple_objects'][1]['multiple_objects_first_name']).to eq('Judge')
          expect(metadata['multiple_objects'][1]['multiple_objects_last_name']).to eq('Hines')
          expect(metadata['multiple_objects'][1]['multiple_objects_position']).to include('King', 'Lord', 'Duke')
        end
      end

      context 'with multiple objects and no fields prefixed' do
        let(:importer) do
          FactoryBot.create(:bulkrax_importer_csv, field_mapping: {
                              'first_name' => { from: ['multiple_objects_first_name'], object: 'multiple_objects' },
                              'last_name' => { from: ['multiple_objects_last_name'], object: 'multiple_objects' },
                              'position' => { from: ['multiple_objects_position'], object: 'multiple_objects' },
                              'language' => { from: ['multiple_objects_language'], object: 'multiple_objects', parsed: true }
                            })
        end

        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:raw_metadata).and_return(
            'source_identifier' => '2',
            'title' => 'some title',
            'multiple_objects_first_name_1' => 'Fake',
            'multiple_objects_last_name_1' => '',
            'multiple_objects_position_1' => 'Leader, Jester, Queen',
            'multiple_objects_language_1' => 'english',
            'multiple_objects_first_name_2' => 'Judge',
            'multiple_objects_last_name_2' => 'Hines',
            'multiple_objects_position_2' => 'King, Lord, Duke'
          )
        end

        it 'succeeds' do
          metadata = subject.build_metadata
          expect(metadata['multiple_objects'][0]['first_name']).to eq('Fake')
          expect(metadata['multiple_objects'][0]['last_name']).to eq('')
          expect(metadata['multiple_objects'][0]['position']).to include('Leader', 'Jester', 'Queen')
          expect(metadata['multiple_objects'][0]['language']).to eq('English')
          expect(metadata['multiple_objects'][1]['first_name']).to eq('Judge')
          expect(metadata['multiple_objects'][1]['last_name']).to eq('Hines')
          expect(metadata['multiple_objects'][1]['position']).to include('King', 'Lord', 'Duke')
        end
      end

      context 'with object fields prefixed and properties with multiple values' do
        let(:importer) do
          FactoryBot.create(:bulkrax_importer_csv, field_mapping: {
                              'multiple_objects_first_name' => { from: ['multiple_objects_first_name'], object: 'multiple_objects' },
                              'multiple_objects_last_name' => { from: ['multiple_objects_last_name'], object: 'multiple_objects' },
                              'multiple_objects_position' => { from: ['multiple_objects_position'], object: 'multiple_objects', nested_type: 'Array' }
                            })
        end

        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:raw_metadata).and_return(
            'source_identifier' => '2',
            'title' => 'some title',
            'multiple_objects_first_name_1' => 'Fake',
            'multiple_objects_last_name_1' => 'Fakerson',
            'multiple_objects_position_1_1' => 'Leader',
            'multiple_objects_position_1_2' => 'Jester',
            'multiple_objects_last_name_2' => 'Hines',
            'multiple_objects_position_2_1' => 'Queen'
          )
        end

        it 'succeeds' do
          metadata = subject.build_metadata
          expect(metadata['multiple_objects'][0]['multiple_objects_first_name']).to eq('Fake')
          expect(metadata['multiple_objects'][0]['multiple_objects_last_name']).to eq('Fakerson')
          expect(metadata['multiple_objects'][0]['multiple_objects_position'][0]).to eq('Leader')
          expect(metadata['multiple_objects'][0]['multiple_objects_position'][1]).to eq('Jester')
          expect(metadata['multiple_objects'][1]['multiple_objects_last_name']).to eq('Hines')
          expect(metadata['multiple_objects'][1]['multiple_objects_position'][0]).to eq('Queen')
        end
      end

      context 'with object fields not prefixed and properties with multiple values' do
        let(:importer) do
          FactoryBot.create(:bulkrax_importer_csv, field_mapping: {
                              'first_name' => { from: ['multiple_objects_first_name'], object: 'multiple_objects' },
                              'last_name' => { from: ['multiple_objects_last_name'], object: 'multiple_objects' },
                              'position' => { from: ['multiple_objects_position'], object: 'multiple_objects', nested_type: 'Array' }
                            })
        end

        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:raw_metadata).and_return(
            'source_identifier' => '2',
            'title' => 'some title',
            'multiple_objects_first_name_1' => 'Fake',
            'multiple_objects_last_name_1' => 'Fakerson',
            'multiple_objects_position_1_1' => 'Leader',
            'multiple_objects_position_1_2' => 'Jester',
            'multiple_objects_last_name_2' => 'Hines',
            'multiple_objects_position_2_1' => 'Queen'
          )
        end

        it 'succeeds' do
          metadata = subject.build_metadata
          expect(metadata['multiple_objects'][0]['first_name']).to eq('Fake')
          expect(metadata['multiple_objects'][0]['last_name']).to eq('Fakerson')
          expect(metadata['multiple_objects'][0]['position'][0]).to eq('Leader')
          expect(metadata['multiple_objects'][0]['position'][1]).to eq('Jester')
          expect(metadata['multiple_objects'][1]['last_name']).to eq('Hines')
          expect(metadata['multiple_objects'][1]['position'][0]).to eq('Queen')
        end
      end
    end

    describe 'reads entry' do
      subject { described_class.new(importerexporter: exporter) }

      context 'with object fields prefixed' do
        let(:exporter) do
          FactoryBot.create(:bulkrax_exporter_worktype, field_mapping: {
                              'id' => { from: ['id'], source_identifier: true },
                              'single_object_first_name' => { from: ['single_object_first_name'], object: 'single_object' },
                              'single_object_last_name' => { from: ['single_object_last_name'], object: 'single_object' },
                              'single_object_position' => { from: ['single_object_position'], object: 'single_object' },
                              'single_object_language' => { from: ['single_object_language'], object: 'single_object', parsed: true }
                            })
        end

        let(:work_obj) do
          Work.new(
            title: ['test'],
            single_object: [{
              'single_object_first_name' => 'Fake',
              'single_object_last_name' => 'Fakerson',
              'single_object_position' => 'Leader, Jester, Queen',
              'single_object_language' => 'english'
            }].to_s
          )
        end

        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:hyrax_record).and_return(work_obj)
          allow(work_obj).to receive(:id).and_return('test123')
          allow(work_obj).to receive(:member_of_work_ids).and_return([])
          allow(work_obj).to receive(:in_work_ids).and_return([])
          allow(work_obj).to receive(:member_work_ids).and_return([])
        end

        it 'succeeds' do
          metadata = subject.build_export_metadata
          expect(metadata['single_object_first_name_1']).to eq('Fake')
          expect(metadata['single_object_last_name_1']).to eq('Fakerson')
          expect(metadata['single_object_position_1']).to include('Leader', 'Jester', 'Queen')
          expect(metadata['single_object_language_1']).to eq('english')
        end
      end

      context 'with object fields and no prefix' do
        let(:exporter) do
          FactoryBot.create(:bulkrax_exporter_worktype, field_mapping: {
                              'id' => { from: ['id'], source_identifier: true },
                              'first_name' => { from: ['single_object_first_name'], object: 'single_object' },
                              'last_name' => { from: ['single_object_last_name'], object: 'single_object' },
                              'position' => { from: ['single_object_position'], object: 'single_object' },
                              'language' => { from: ['single_object_language'], object: 'single_object', parsed: true }
                            })
        end

        let(:work_obj) do
          Work.new(
            title: ['test'],
            single_object: [{
              'first_name' => 'Fake',
              'last_name' => 'Fakerson',
              'position' => 'Leader, Jester, Queen',
              'language' => 'english'
            }].to_s
          )
        end

        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:hyrax_record).and_return(work_obj)
          allow(work_obj).to receive(:id).and_return('test123')
          allow(work_obj).to receive(:member_of_work_ids).and_return([])
          allow(work_obj).to receive(:in_work_ids).and_return([])
          allow(work_obj).to receive(:member_work_ids).and_return([])
        end

        it 'succeeds' do
          metadata = subject.build_export_metadata
          expect(metadata['single_object_first_name_1']).to eq('Fake')
          expect(metadata['single_object_last_name_1']).to eq('Fakerson')
          expect(metadata['single_object_position_1']).to include('Leader', 'Jester', 'Queen')
          expect(metadata['single_object_language_1']).to eq('english')
        end
      end

      context 'with multiple objects and fields prefixed' do
        let(:exporter) do
          FactoryBot.create(:bulkrax_exporter_worktype, field_mapping: {
                              'id' => { from: ['id'], source_identifier: true },
                              'multiple_objects_first_name' => { from: ['multiple_objects_first_name'], object: 'multiple_objects' },
                              'multiple_objects_last_name' => { from: ['multiple_objects_last_name'], object: 'multiple_objects' },
                              'multiple_objects_position' => { from: ['multiple_objects_position'], object: 'multiple_objects' },
                              'multiple_objects_language' => { from: ['multiple_objects_language'], object: 'multiple_objects', parsed: true }
                            })
        end

        let(:work_obj) do
          Work.new(
            title: ['test'],
            multiple_objects: [
              [
                {
                  'multiple_objects_first_name' => 'Fake',
                  'multiple_objects_last_name' => 'Fakerson',
                  'multiple_objects_position' => 'Leader, Jester, Queen',
                  'multiple_objects_language' => 'english'
                },
                {
                  'multiple_objects_first_name' => 'Judge',
                  'multiple_objects_last_name' => 'Hines',
                  'multiple_objects_position' => 'King, Lord, Duke'
                }
              ].to_s
            ]
          )
        end

        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:hyrax_record).and_return(work_obj)
          allow(work_obj).to receive(:id).and_return('test123')
          allow(work_obj).to receive(:member_of_work_ids).and_return([])
          allow(work_obj).to receive(:in_work_ids).and_return([])
          allow(work_obj).to receive(:member_work_ids).and_return([])
        end

        it 'succeeds' do
          metadata = subject.build_export_metadata
          expect(metadata['multiple_objects_first_name_1']).to eq('Fake')
          expect(metadata['multiple_objects_last_name_1']).to eq('Fakerson')
          expect(metadata['multiple_objects_position_1']).to include('Leader, Jester, Queen')
          expect(metadata['multiple_objects_language_1']).to eq('english')
          expect(metadata['multiple_objects_first_name_2']).to eq('Judge')
          expect(metadata['multiple_objects_last_name_2']).to eq('Hines')
          expect(metadata['multiple_objects_position_2']).to include('King, Lord, Duke')
        end
      end

      context 'with multiple objects and no fields prefixed' do
        let(:exporter) do
          FactoryBot.create(:bulkrax_exporter_worktype, field_mapping: {
                              'id' => { from: ['id'], source_identifier: true },
                              'first_name' => { from: ['multiple_objects_first_name'], object: 'multiple_objects' },
                              'last_name' => { from: ['multiple_objects_last_name'], object: 'multiple_objects' },
                              'position' => { from: ['multiple_objects_position'], object: 'multiple_objects' },
                              'language' => { from: ['multiple_objects_language'], object: 'multiple_objects', parsed: true }
                            })
        end

        let(:work_obj) do
          Work.new(
            title: ['test'],
            multiple_objects: [
              [
                {
                  'first_name' => 'Fake',
                  'last_name' => 'Fakerson',
                  'position' => 'Leader, Jester, Queen',
                  'language' => 'english'
                },
                {
                  'first_name' => 'Judge',
                  'last_name' => 'Hines',
                  'position' => 'King, Lord, Duke'
                }
              ].to_s
            ]
          )
        end

        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:hyrax_record).and_return(work_obj)
          allow(work_obj).to receive(:id).and_return('test123')
          allow(work_obj).to receive(:member_of_work_ids).and_return([])
          allow(work_obj).to receive(:in_work_ids).and_return([])
          allow(work_obj).to receive(:member_work_ids).and_return([])
        end

        it 'succeeds' do
          metadata = subject.build_export_metadata
          expect(metadata['multiple_objects_first_name_1']).to eq('Fake')
          expect(metadata['multiple_objects_last_name_1']).to eq('Fakerson')
          expect(metadata['multiple_objects_position_1']).to include('Leader, Jester, Queen')
          expect(metadata['multiple_objects_language_1']).to eq('english')
          expect(metadata['multiple_objects_first_name_2']).to eq('Judge')
          expect(metadata['multiple_objects_last_name_2']).to eq('Hines')
          expect(metadata['multiple_objects_position_2']).to include('King, Lord, Duke')
        end
      end

      context 'with object fields prefixed and properties with multiple values' do
        let(:exporter) do
          FactoryBot.create(:bulkrax_exporter_worktype, field_mapping: {
                              'id' => { from: ['id'], source_identifier: true },
                              'multiple_objects_first_name' => { from: ['multiple_objects_first_name'], object: 'multiple_objects' },
                              'multiple_objects_last_name' => { from: ['multiple_objects_last_name'], object: 'multiple_objects' },
                              'multiple_objects_position' => { from: ['multiple_objects_position'], object: 'multiple_objects', nested_type: 'Array' }
                            })
        end

        let(:work_obj) do
          Work.new(
            title: ['test'],
            multiple_objects: [
              [
                {
                  'multiple_objects_first_name' => 'Fake',
                  'multiple_objects_last_name' => 'Fakerson'
                },
                {
                  'multiple_objects_first_name' => 'Judge',
                  'multiple_objects_last_name' => 'Hines',
                  'multiple_objects_position' => ['King', 'Lord', 'Duke']
                }
              ].to_s
            ]
          )
        end

        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:hyrax_record).and_return(work_obj)
          allow(work_obj).to receive(:id).and_return('test123')
          allow(work_obj).to receive(:member_of_work_ids).and_return([])
          allow(work_obj).to receive(:in_work_ids).and_return([])
          allow(work_obj).to receive(:member_work_ids).and_return([])
        end

        it 'succeeds' do
          metadata = subject.build_export_metadata
          expect(metadata['multiple_objects_first_name_1']).to eq('Fake')
          expect(metadata['multiple_objects_last_name_1']).to eq('Fakerson')
          expect(metadata['multiple_objects_first_name_2']).to eq('Judge')
          expect(metadata['multiple_objects_last_name_2']).to eq('Hines')
          expect(metadata['multiple_objects_position_2_1']).to eq('King')
          expect(metadata['multiple_objects_position_2_2']).to eq('Lord')
          expect(metadata['multiple_objects_position_2_3']).to eq('Duke')
        end
      end

      context 'with object fields not prefixed and properties with multiple values' do
        let(:exporter) do
          FactoryBot.create(:bulkrax_exporter_worktype, field_mapping: {
                              'id' => { from: ['id'], source_identifier: true },
                              'first_name' => { from: ['multiple_objects_first_name'], object: 'multiple_objects' },
                              'last_name' => { from: ['multiple_objects_last_name'], object: 'multiple_objects' },
                              'position' => { from: ['multiple_objects_position'], object: 'multiple_objects', nested_type: 'Array' }
                            })
        end

        let(:work_obj) do
          Work.new(
            title: ['test'],
            multiple_objects: [
              [
                {
                  'first_name' => 'Fake',
                  'last_name' => 'Fakerson'
                },
                {
                  'first_name' => 'Judge',
                  'last_name' => 'Hines',
                  'position' => ['King', 'Lord', 'Duke']
                }
              ].to_s
            ]
          )
        end

        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:hyrax_record).and_return(work_obj)
          allow(work_obj).to receive(:id).and_return('test123')
          allow(work_obj).to receive(:member_of_work_ids).and_return([])
          allow(work_obj).to receive(:in_work_ids).and_return([])
          allow(work_obj).to receive(:member_work_ids).and_return([])
        end

        it 'succeeds' do
          metadata = subject.build_export_metadata
          expect(metadata['multiple_objects_first_name_1']).to eq('Fake')
          expect(metadata['multiple_objects_last_name_1']).to eq('Fakerson')
          expect(metadata['multiple_objects_first_name_2']).to eq('Judge')
          expect(metadata['multiple_objects_last_name_2']).to eq('Hines')
          expect(metadata['multiple_objects_position_2_1']).to eq('King')
          expect(metadata['multiple_objects_position_2_2']).to eq('Lord')
          expect(metadata['multiple_objects_position_2_3']).to eq('Duke')
        end
      end
    end

    describe '#add_parent_to_import_run' do
      subject(:entry) { described_class.new(importerexporter: importer) }
      let(:importer) { FactoryBot.build(:bulkrax_importer_csv, importer_runs: [importer_run]) }
      let(:importer_run) { build(:bulkrax_importer_run) }

      it 'adds the parent_id to the run' do
        expect(importer_run.parents).to eq([])

        entry.add_parent_to_import_run('dummy', importer_run)

        expect(importer_run.parents).to eq(['dummy'])
      end
    end

    describe '#build_relationship_metadata' do
      subject(:entry) { described_class.new(importerexporter: exporter) }
      let(:exporter) { create(:bulkrax_exporter, :with_relationships_mappings) }
      let(:hyrax_record) do
        OpenStruct.new(
          has_model: ['Work'],
          source: 'test',
          member_of_collections: [],
          file_sets: []
        )
      end

      before do
        allow(entry).to receive(:hyrax_record).and_return(hyrax_record)
        allow(entry).to receive(:source_identifier).and_return('source_identifier')
        allow(entry).to receive(:work_identifier).and_return('source')
      end

      it 'gets called by #build_export_metadata' do
        expect(entry).to receive(:build_relationship_metadata).once
        entry.build_export_metadata
      end

      context 'when parser does not have relationship field mappings' do
        it 'does not raise an error' do
          expect { entry.build_relationship_metadata }.not_to raise_error
        end

        it "does not change the entry's parsed_metadata" do
          expect { entry.build_relationship_metadata }.not_to change { entry.parsed_metadata }
        end
      end

      context 'when parser has relationship field mappings' do
        let(:exporter) { create(:bulkrax_exporter, :with_relationships_mappings) }

        before do
          entry.parsed_metadata = {}
          entry.build_relationship_metadata
        end

        context "when the entry's record does not have any relationships" do
          it 'does not add any relationships to the parsed_metadata' do
            expect(entry.parsed_metadata.keys).not_to include('parents')
            expect(entry.parsed_metadata.keys).not_to include('children')
          end
        end

        context "when the entry's record has relationships" do
          let(:hyrax_record) do
            OpenStruct.new(
              member_of_collection_ids: %w[pc1 pc2],
              member_of_work_ids: %w[pw1 pw2],
              in_work_ids: %w[pw3 pw4], # used by FileSets
              member_collection_ids: %w[cc1 cc2],
              member_work_ids: %w[cw1 cw2],
              file_set_ids: %w[cfs1 cfs2]
            )
          end

          it 'adds all the parent relationships to the parent field mapping' do
            expect(entry.parsed_metadata['parents_1']).to eq('pc1')
            expect(entry.parsed_metadata['parents_2']).to eq('pc2')
            expect(entry.parsed_metadata['parents_3']).to eq('pw1')
            expect(entry.parsed_metadata['parents_4']).to eq('pw2')
            expect(entry.parsed_metadata['parents_5']).to eq('pw3')
            expect(entry.parsed_metadata['parents_6']).to eq('pw4')
          end

          it 'adds all the child relationships to the child field mapping' do
            expect(entry.parsed_metadata['children_1']).to eq('cc1')
            expect(entry.parsed_metadata['children_2']).to eq('cc2')
            expect(entry.parsed_metadata['children_3']).to eq('cw1')
            expect(entry.parsed_metadata['children_4']).to eq('cw2')
            expect(entry.parsed_metadata['children_5']).to eq('cfs1')
            expect(entry.parsed_metadata['children_6']).to eq('cfs2')
          end

          context 'with a join setting' do
            let(:exporter) { create(:bulkrax_exporter, field_mapping: field_mapping) }
            let(:field_mapping) do
              {
                'parents' => { 'from' => ['parents_column'], join: true, split: /\s*[|]\s*/, related_parents_field_mapping: true },
                'children' => { 'from' => ['children_column'], join: true, split: /\s*[|]\s*/, related_children_field_mapping: true }
              }
            end

            it 'joins the values into a single column' do
              expect(entry.parsed_metadata['parents']).to eq('pc1 | pc2 | pw1 | pw2 | pw3 | pw4')
              expect(entry.parsed_metadata['children']).to eq('cc1 | cc2 | cw1 | cw2 | cfs1 | cfs2')
            end
          end
        end
      end
    end

    describe '#build_files' do
      subject(:entry) { described_class.new(importerexporter: exporter) }
      let(:exporter) { create(:bulkrax_exporter, :with_relationships_mappings) }

      before do
        allow(entry).to receive(:hyrax_record).and_return(hyrax_record)
      end

      context 'when entry#hyrax_record is a Collection' do
        let(:hyrax_record) do
          OpenStruct.new(
            has_model: ['Collection'],
            source: 'test',
            member_of_collections: [],
            file_set?: false
          )
        end

        before do
          allow(hyrax_record).to receive(:is_a?).with(FileSet).and_return(false)
          allow(hyrax_record).to receive(:is_a?).with(Collection).and_return(true)
          allow(entry).to receive(:source_identifier).and_return('source_identifier')
          allow(entry).to receive(:work_identifier).and_return('source')
        end

        it 'does not get called by #build_export_metadata' do
          expect(entry).not_to receive(:build_files)
          entry.build_export_metadata
        end
      end

      context 'when entry#hyrax_record is a FileSet' do
        let(:hyrax_record) do
          OpenStruct.new(
            has_model: ['FileSet'],
            file_set?: true
          )
        end

        before do
          entry.parsed_metadata = {}
          allow(hyrax_record).to receive(:is_a?).with(FileSet).and_return(true)
          allow(hyrax_record).to receive(:is_a?).with(Collection).and_return(false)
          allow(entry).to receive(:filename).and_return('hello.png')
        end

        it 'gets called by #build_export_metadata' do
          expect(entry).to receive(:build_files).once
          entry.build_export_metadata
        end

        context 'when the parser has a file field mapping' do
          context 'with join set to true' do
            let(:exporter) { create(:bulkrax_exporter, field_mapping: { 'file' => { from: ['filename'], join: true } }) }

            it "adds the file set's filename to the file mapping in parsed_metadata" do
              entry.build_files

              expect(entry.parsed_metadata['filename']).to eq('hello.png')
            end
          end
        end

        context 'when the parser does not have a file field mapping' do
          it "adds the file set's filename to the 'file' key in parsed_metadata" do
            entry.build_files

            expect(entry.parsed_metadata['file_1']).to eq('hello.png')
          end
        end
      end

      context 'when entry#hyrax_record is a Work' do
        let(:hyrax_record) do
          OpenStruct.new(
            has_model: ['Work'],
            work?: true,
            file_set?: false,
            file_sets: [file_set_1, file_set_2],
            member_of_collections: []
          )
        end
        let(:file_set_1) do
          OpenStruct.new(
            id: 'file_set_1',
            original_file: OpenStruct.new(
              file_name: ['hello.png'],
              mime_type: 'image/png'
            )
          )
        end
        let(:file_set_2) do
          OpenStruct.new(
            id: 'file_set_2',
            original_file: OpenStruct.new(
              file_name: ['world.jpg'],
              mime_type: 'image/jpeg'
            )
          )
        end

        before do
          entry.parsed_metadata = {}
          allow(hyrax_record).to receive(:is_a?).with(FileSet).and_return(false)
          allow(hyrax_record).to receive(:is_a?).with(Collection).and_return(false)
        end

        it 'gets called by #build_export_metadata' do
          expect(entry).to receive(:build_files).once
          entry.build_export_metadata
        end

        it 'calls #build_thumbnail_files' do
          expect(entry).to receive(:build_thumbnail_files).once
          entry.build_files
        end

        context 'when the parser has a file field mapping' do
          context 'with join set to true' do
            let(:exporter) { create(:bulkrax_exporter, field_mapping: { 'file' => { from: ['filename'], join: true } }) }

            it "adds the work's file set's filenames to the file mapping in parsed_metadata" do
              entry.build_files

              expect(entry.parsed_metadata['filename']).to eq('hello.png | world.jpg')
            end
          end
        end

        context 'when the parser does not have a file field mapping' do
          it "adds the work's file set's filenames to the 'file' key in parsed_metadata" do
            entry.build_files

            expect(entry.parsed_metadata['file_1']).to eq('hello.png')
            expect(entry.parsed_metadata['file_2']).to eq('world.jpg')
          end
        end
      end
    end

    describe '#build_thumbnail_files' do
      subject(:entry) { described_class.new(importerexporter: exporter) }
      let(:exporter) { create(:bulkrax_exporter, :with_relationships_mappings, include_thumbnails: false) }

      before do
        allow(entry).to receive(:hyrax_record).and_return(hyrax_record)
      end

      context 'when record is a work' do
        let(:hyrax_record) do
          OpenStruct.new(
            has_model: ['Work'],
            work?: true,
            thumbnail: [file_set_1],
            file_sets: [file_set_2],
            member_of_collections: []
          )
        end
        let(:file_set_1) do
          OpenStruct.new(
            id: 'file_set_1',
            original_file: OpenStruct.new(
              file_name: ['hello.png'],
              mime_type: 'image/png'
            )
          )
        end
        let(:file_set_2) do
          OpenStruct.new(
            id: 'file_set_2',
            original_file: OpenStruct.new(
              file_name: ['world.jpg'],
              mime_type: 'image/jpeg'
            )
          )
        end

        before do
          entry.parsed_metadata = {}
          allow(hyrax_record).to receive(:is_a?).with(FileSet).and_return(false)
        end
 
        it 'gets called by #build_files' do
          expect(entry).to receive(:build_thumbnail_files).once
          entry.build_files
        end

        context 'when exporter does not include thumbnails' do
          it 'does not include a thumbnail_file header' do
            entry.build_thumbnail_files

            expect(entry.parsed_metadata).to eq({})
          end
        end

        context 'when exporter includes thumbnails' do
          it "adds the work's file set's filenames to the 'thumbnail_file' key in parsed_metadata" do
            exporter.include_thumbnails = true

            entry.build_thumbnail_files

            expect(entry.parsed_metadata["thumbnail_file_1"]).to eq('hello.png')
          end
        end
      end
    end

    describe '#handle_join_on_export' do
      subject(:entry) { described_class.new(importerexporter: exporter, parsed_metadata: {}) }
      let(:exporter) { create(:bulkrax_exporter) }

      context 'when a field mapping is configured to join values' do
        it 'joins the values into a single column' do
          entry.handle_join_on_export('dummy', %w[a1 b2 c3], true)

          expect(entry.parsed_metadata['dummy']).to eq('a1 | b2 | c3')
        end
      end

      context 'when a field mapping is not configured to join values' do
        it 'lists the values in separate, numerated columns' do
          entry.handle_join_on_export('dummy', %w[a1 b2 c3], false)

          expect(entry.parsed_metadata['dummy']).to be_nil
          expect(entry.parsed_metadata['dummy_1']).to eq('a1')
          expect(entry.parsed_metadata['dummy_2']).to eq('b2')
          expect(entry.parsed_metadata['dummy_3']).to eq('c3')
        end
      end
    end
  end
end
# rubocop: enable Metrics/BlockLength
