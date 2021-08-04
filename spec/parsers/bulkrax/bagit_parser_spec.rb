# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe BagitParser do
    subject { described_class.new(importer) }
    let(:importer) { FactoryBot.create(:bulkrax_importer_bagit) }

    before do
      Bulkrax.source_identifier_field_mapping = { 'Bulkrax::RdfEntry' => 'source_identifier' }
      allow(entry).to receive(:id)
      allow(Bulkrax::ImportWorkJob).to receive(:perform_later)
    end

    describe 'Bag or Bags with RDF Metadata' do
      let(:entry) { FactoryBot.create(:bulkrax_rdf_entry, importerexporter: importer) }
      let(:parser_fields) do
        {
          'metadata_file_name' => 'descMetadata.nt',
          'metadata_format' => 'Bulkrax::RdfEntry'
        }
      end

      before do
        allow(Bulkrax::RdfEntry).to receive_message_chain(:where, :first_or_create!).and_return(entry)
        importer.parser_fields = parser_fields
      end

      context 'Bag containing RDF' do
        before do
          importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/bag"
        end

        it 'creates the entry and increments the counters' do
          expect(subject).to receive(:increment_counters).once
          subject.create_works
        end
      end

      context 'Bag with no metadata' do
        before do
          importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/bag_nometadata"
        end

        it 'Raises an error' do
          subject.create_works
          expect(importer.last_error['error_class']).to eq('StandardError')
        end
      end

      context 'Invalid - not a bag' do
        before do
          importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/spec/fixtures/bags/not_a_bag"
        end

        it 'Raises an error' do
          subject.create_works
          expect(importer.last_error['error_class']).to eq('StandardError')
        end
      end

      context 'Bag containing folders' do
        before do
          importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/bag_of_folders"
        end

        it 'creates the entry and increments the counters' do
          expect(subject).to receive(:increment_counters).once
          subject.create_works
        end
      end

      context 'Folder containing bags' do
        before do
          importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/folder_of_bags"
        end

        it 'creates the entry and increments the counters' do
          expect(subject).to receive(:increment_counters).once
          subject.create_works
        end
      end
    end

    describe 'Bag with CSV' do
      let(:entry) { FactoryBot.create(:bulkrax_csv_entry, importerexporter: importer) }
      let(:parser_fields) do
        {
          'import_file_path' => './spec/fixtures/bags/bag_with_csv',
          'metadata_file_name' => 'metadata.csv',
          'metadata_format' => 'Bulkrax::CsvEntry'
        }
      end

      before do
        allow(Bulkrax::CsvEntry).to receive_message_chain(:where, :first_or_create!).and_return(entry)
        importer.parser_fields = parser_fields
      end

      context 'Bag containing CSV' do
        it 'creates the entry and increments the counters' do
          expect(subject).to receive(:increment_counters).once
          subject.create_works
        end
      end

      context 'Incorrect metadata filename' do
        before do
          importer.parser_fields['metadata_file_name'] = 'descMetadata.nt'
        end

        it 'Raises an error' do
          subject.create_works
          expect(importer.last_error['error_class']).to eq('StandardError')
        end
      end
    end
  end
end
