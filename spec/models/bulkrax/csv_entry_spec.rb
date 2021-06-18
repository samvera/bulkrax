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
    end
  end
end
