# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe CsvEntry, type: :model do
    describe 'builds entry' do
      subject { described_class.new(importerexporter: importer) }
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }

      context 'without required metadata' do
        before do
          allow(subject).to receive(:record).and_return(source_identifier: '1', some_field: 'some data')
        end

        it 'fails and stores an error' do
          expect { subject.build_metadata }.to raise_error(StandardError)
        end
      end

      context 'with required metadata' do
        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:record).and_return('source_identifier' => '2', 'title' => 'some title')
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

      context 'with enumerated columns appended' do
        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:record).and_return('source_identifier' => '2', 'title_1' => 'some title', 'title_2' => 'another title')
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
          allow(subject).to receive(:record).and_return('source_identifier' => '2', '1_title' => 'some title', '2_title' => 'another title')
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

          allow(subject).to receive(:record).and_return('source_identifier' => '3', 'title' => 'some title')
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
          allow(subject).to receive(:record).and_return(
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
          allow(subject).to receive(:record).and_return(
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
          allow(subject).to receive(:record).and_return(
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

        # rubocop:disable RSpec/ExampleLength
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
          allow(subject).to receive(:record).and_return(
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
          allow(subject).to receive(:record).and_return(
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
          allow(subject).to receive(:record).and_return(
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
        end

        it 'succeeds' do
          metadata = subject.build_export_metadata
          expect(metadata['first_name_1']).to eq('Fake')
          expect(metadata['last_name_1']).to eq('Fakerson')
          expect(metadata['position_1']).to include('Leader', 'Jester', 'Queen')
          expect(metadata['language_1']).to eq('english')
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
        end

        it 'succeeds' do
          metadata = subject.build_export_metadata
          expect(metadata['first_name_1']).to eq('Fake')
          expect(metadata['last_name_1']).to eq('Fakerson')
          expect(metadata['position_1']).to include('Leader, Jester, Queen')
          expect(metadata['language_1']).to eq('english')
          expect(metadata['first_name_2']).to eq('Judge')
          expect(metadata['last_name_2']).to eq('Hines')
          expect(metadata['position_2']).to include('King, Lord, Duke')
        end
      end

      context 'with object fields prefixed and properties with multiple values' do
        let(:exporter) do
          FactoryBot.create(:bulkrax_exporter_worktype, field_mapping: {
                              'id' => { from: ['id'], source_identifier: true },
                              'multiple_objects_first_name' => { from: ['multiple_objects_first_name'], object: 'multiple_objects' },
                              'multiple_objects_last_name' => { from: ['multiple_objects_last_name'], object: 'multiple_objects' },
                              'multiple_objects_position' => { from: ['multiple_objects_position'], object: 'multiple_objects', nested_type: 'Array' },
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
                  'multiple_objects_position' => ['Leader, Jester, Queen'],
                },
                {
                  'multiple_objects_first_name' => 'Judge',
                  'multiple_objects_last_name' => 'Hines',
                  'multiple_objects_position' => ['King, Lord, Duke'],
                }
              ].to_s
            ]
          )
        end

        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:hyrax_record).and_return(work_obj)
          allow(work_obj).to receive(:id).and_return('test123')
        end

        it 'succeeds' do
          metadata = subject.build_export_metadata
          byebug
        end
      end
      # rubocop:enable RSpec/ExampleLength
    end
  end
end
