# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe BagitParser do
    let(:rdf_importer) { FactoryBot.create(:bulkrax_importer_bagit_rdf) }
    let(:csv_importer) { FactoryBot.create(:bulkrax_importer_bagit_csv) }
    
    describe '.export_supported?' do
      it 'returns true' do
        expect(described_class.export_supported?).to be true
      end
    end
    
    context 'as an RDF parser' do
      subject { described_class.new(rdf_importer) }
      describe '#valid_import?' do
        it 'returns true if importer_fields are present' do
          expect(subject.valid_import?).to be true
        end

        it  'returns false if importer_fields are not present' do
          rdf_importer.parser_fields = nil
          expect(subject.valid_import?).to be false
        end
      end

      describe 'Bag or Bags with RDF Metadata' do
        let(:entry) { FactoryBot.create(:bulkrax_rdf_entry, importerexporter: rdf_importer) }
        let(:parser_fields) do
          {
            'metadata_file_name' => 'descMetadata.nt',
            'metadata_format' => 'Bulkrax::RdfEntry'
          }
        end

        before do
          allow(Bulkrax::RdfEntry).to receive_message_chain(:where, :first_or_create!).and_return(entry)
          rdf_importer.parser_fields = parser_fields
        end

        context 'Bag containing RDF' do
          before do
            rdf_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/bag"
          end

          it 'creates the entry and increments the counters' do
            expect(subject).to receive(:increment_counters).once
            subject.create_works
          end
        end

        context 'Bag with no metadata' do
          before do
            rdf_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/bag_nometadata"
          end

          it 'Raises an error' do
            subject.create_works
            expect(rdf_importer.last_error['error_class']).to eq('StandardError')
          end
        end

        context 'Invalid - not a bag' do
          before do
            rdf_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/spec/fixtures/bags/not_a_bag"
          end

          it 'Raises an error' do
            subject.create_works
            expect(rdf_importer.last_error['error_class']).to eq('StandardError')
          end
        end

        context 'Bag containing folders' do
          before do
            rdf_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/bag_of_folders_with_rdf"
          end

          it 'creates the entry and increments the counters' do
            expect(subject).to receive(:increment_counters).once
            subject.create_works
          end
        end

        context 'Folder containing bags' do
          before do
            rdf_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/folder_of_bags_with_rdf"
          end

          it 'creates the entry and increments the counters' do
            expect(subject).to receive(:increment_counters).once
            subject.create_works
          end
        end
      end

      describe 'Bag with CSV' do
        let(:entry) { FactoryBot.create(:bulkrax_csv_entry, importerexporter: rdf_importer) }
        let(:parser_fields) do
          {
            'import_file_path' => './spec/fixtures/bags/bag_with_csv',
            'metadata_file_name' => 'metadata.csv',
            'metadata_format' => 'Bulkrax::CsvEntry'
          }
        end

        before do
          allow(Bulkrax::CsvEntry).to receive_message_chain(:where, :first_or_create!).and_return(entry)
          rdf_importer.parser_fields = parser_fields
        end

        context 'Bag containing CSV' do
          it 'creates the entry and increments the counters' do
            expect(subject).to receive(:increment_counters).once
            subject.create_works
          end
        end

        context 'Incorrect metadata filename' do
          before do
            rdf_importer.parser_fields['metadata_file_name'] = 'descMetadata.nt'
          end

          it 'Raises an error' do
            subject.create_works
            expect(rdf_importer.last_error['error_class']).to eq('StandardError')
          end
        end
      end
    end

    context 'as a CSV parser' do
      subject { described_class.new(csv_importer) }
      describe '#valid_import?' do
        it 'returns true if importer_fields are present' do
          expect(subject.valid_import?).to be true
        end

        it  'returns false if importer_fields are not present' do
          csv_importer.parser_fields = nil
          expect(subject.valid_import?).to be false
        end
      end

      describe 'Bag or Bags with CSV Metadata' do
        let(:entry) { FactoryBot.create(:bulkrax_csv_entry, importerexporter: csv_importer) }
        let(:parser_fields) do
          {
            'metadata_file_name' => 'metadata.csv',
            'metadata_format' => 'Bulkrax::CsvEntry'
          }
        end

        before do
          allow(Bulkrax::CsvEntry).to receive_message_chain(:where, :first_or_create!).and_return(entry)
          csv_importer.parser_fields = parser_fields
        end

        context 'Bag containing CSV' do
          before do
            csv_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/bag_with_csv"
          end

          it 'creates the entry and increments the counters' do
            expect(subject).to receive(:increment_counters).once
            subject.create_works
          end
        end

        context 'Bag with no metadata' do
          before do
            csv_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/bag_nometadata"
          end

          it 'Raises an error' do
            subject.create_works
            expect(csv_importer.last_error['error_class']).to eq('StandardError')
          end
        end

        context 'Invalid - not a bag' do
          before do
            csv_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/spec/fixtures/bags/not_a_bag"
          end

          it 'Raises an error' do
            subject.create_works
            expect(csv_importer.last_error['error_class']).to eq('StandardError')
          end
        end

        context 'Bag containing folders' do
          before do
            csv_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/bag_of_folders_with_csv"
          end

          it 'creates the entry and increments the counters' do
            expect(subject).to receive(:increment_counters).once
            subject.create_works
          end
        end

        context 'Folder containing bags' do
          before do
            csv_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/folder_of_bags_with_csv"
          end

          it 'creates the entry and increments the counters' do
            expect(subject).to receive(:increment_counters).once
            subject.create_works
          end
        end
      end

      describe 'Bag with CSV' do
        let(:entry) { FactoryBot.create(:bulkrax_csv_entry, importerexporter: csv_importer) }
        let(:parser_fields) do
          {
            'import_file_path' => './spec/fixtures/bags/bag_with_csv',
            'metadata_file_name' => 'metadata.csv',
            'metadata_format' => 'Bulkrax::CsvEntry'
          }
        end

        before do
          allow(Bulkrax::CsvEntry).to receive_message_chain(:where, :first_or_create!).and_return(entry)
          csv_importer.parser_fields = parser_fields
        end

        context 'Bag containing CSV' do
          it 'creates the entry and increments the counters' do
            expect(subject).to receive(:increment_counters).once
            subject.create_works
          end
        end

        context 'Incorrect metadata filename' do
          before do
            csv_importer.parser_fields['metadata_file_name'] = 'descMetadata.nt'
          end

          it 'Raises an error' do
            subject.create_works
            expect(csv_importer.last_error['error_class']).to eq('StandardError')
          end
        end
      end
    end
  end
end
