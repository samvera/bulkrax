# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe CsvEntry, type: :model do
    describe 'builds entry' do
      subject { described_class.new(importerexporter: importer) }
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }

      before do
        Bulkrax.default_work_type = 'Work'
      end

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
                              'creator_first_name' => { from: ['creator_first_name'], object: 'creator' },
                              'creator_last_name' => { from: ['creator_last_name'], object: 'creator' },
                              'creator_position' => { from: ['creator_position'], object: 'creator' },
                              'creator_language' => { from: ['creator_language'], object: 'creator', parsed: true }
                            })
        end

        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:record).and_return(
            'source_identifier' => '2',
            'title' => 'some title',
            'creator_first_name' => 'Fake',
            'creator_last_name' => 'Fakerson',
            'creator_position' => 'Leader, Jester, Queen',
            'creator_language' => 'english'
          )
        end

        it 'succeeds' do
          metadata = subject.build_metadata
          # puts "METADATA>> #{metadata}"
          # metadata = {
          #   "source"=>["2"],
          #   "title"=>["some title"],
          #   "creator"=>{
          #     "creator_first_name"=>"Fake",
          #     "creator_last_name"=>"Fakerson",
          #     "creator_position"=>"Leader, Jester, Queen",
          #     "creator_language"=>"English"
          #   },
          #   "file"=>[],
          #   "visibility"=>"open",
          #   "rights_statement"=>[nil],
          #   "admin_set_id"=>"MyString"
          # }

          expect(metadata['creator']['creator_first_name']).to eq('Fake')
          expect(metadata['creator']['creator_last_name']).to eq('Fakerson')
          expect(metadata['creator']['creator_position']).to include('Leader', 'Jester', 'Queen')
          expect(metadata['creator']['creator_language']).to eq('English')
        end
      end

      context 'with object fields and no prefix' do
        let(:importer) do
          FactoryBot.create(:bulkrax_importer_csv, field_mapping: {
                              'first_name' => { from: ['creator_first_name'], object: 'creator' },
                              'last_name' => { from: ['creator_last_name'], object: 'creator' },
                              'position' => { from: ['creator_position'], object: 'creator' },
                              'language' => { from: ['creator_language'], object: 'creator', parsed: true }
                            })
        end

        before do
          allow_any_instance_of(ObjectFactory).to receive(:run!)
          allow(subject).to receive(:record).and_return(
            'source_identifier' => '2',
            'title' => 'some title',
            'creator_first_name' => 'Fake',
            'creator_last_name' => 'Fakerson',
            'creator_position' => 'Leader, Jester, Queen',
            'creator_language' => 'english'
          )
        end

        it 'succeeds' do
          metadata = subject.build_metadata
          expect(metadata['creator']['first_name']).to eq('Fake')
          expect(metadata['creator']['last_name']).to eq('Fakerson')
          expect(metadata['creator']['position']).to include('Leader', 'Jester', 'Queen')
          expect(metadata['creator']['language']).to eq('English')
        end
      end
    end
  end
end
