# frozen_string_literal: true

require 'rails_helper'
require 'bagit'

module Bulkrax
  RSpec.describe BagitParser do
    context 'when importing a bagit file' do
      let(:rdf_importer) { FactoryBot.create(:bulkrax_importer_bagit_rdf) }
      let(:csv_importer) { FactoryBot.create(:bulkrax_importer_bagit_csv) }

      describe '.export_supported?' do
        it 'returns true' do
          expect(described_class.export_supported?).to be true
        end
      end

      context 'as an RDF entry' do
        subject { described_class.new(rdf_importer) }
        describe '#valid_import?' do
          it 'returns true if importer_fields are present' do
            expect(subject.valid_import?).to be true
          end

          it 'returns false if importer_fields are not present' do
            rdf_importer.parser_fields = nil
            expect(subject.valid_import?).to be false
          end
        end

        describe 'Bag or Bags with RDF Metadata' do
          let(:entry) { FactoryBot.create(:bulkrax_rdf_entry, importerexporter: rdf_importer) }

          before do
            allow(Bulkrax::RdfEntry).to receive_message_chain(:where, :first_or_create!).and_return(entry)
          end

          context 'Bag containing RDF' do
            it 'creates the entry and increments the counters' do
              expect(subject).to receive(:increment_counters).once
              subject.create_works
            end
          end

          context 'Bag with no metadata' do
            it 'Raises an error' do
              rdf_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/bag_nometadata"

              subject.create_works
              expect(rdf_importer.last_error['error_class']).to eq('StandardError')
            end
          end

          context 'Invalid - not a bag' do
            it 'Raises an error' do
              rdf_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/spec/fixtures/bags/not_a_bag"

              subject.create_works
              expect(rdf_importer.last_error['error_class']).to eq('StandardError')
            end
          end

          context 'Bag containing folders' do
            it 'creates the entry and increments the counters' do
              rdf_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/bag_of_folders_with_rdf"

              expect(subject).to receive(:increment_counters).once
              subject.create_works
            end
          end

          context 'Folder containing bags' do
            it 'creates the entry and increments the counters' do
              rdf_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/folder_of_bags_with_rdf"

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
            it 'creates the collection entry and increments the counters' do
              expect(subject).to receive(:increment_counters).once
              subject.create_collections
            end

            it 'creates the work entry and increments the counters' do
              expect(subject).to receive(:increment_counters).once
              subject.create_works
            end

            it 'creates the file set entry and increments the counters' do
              expect(subject).to receive(:increment_counters).once
              subject.create_file_sets
            end
          end

          context 'Incorrect metadata filename' do
            before do
              rdf_importer.parser_fields['metadata_file_name'] = 'metadata.nt'
            end

            it 'Raises an error' do
              subject.create_works
              expect(rdf_importer.last_error['error_class']).to eq('StandardError')
            end
          end
        end
      end

      context 'as a CSV entry' do
        subject { described_class.new(csv_importer) }

        before do
          allow(::Hyrax.config).to receive(:curation_concerns).and_return([Work])
        end

        describe '#valid_import?' do
          it 'returns true if importer_fields are present' do
            expect(subject.valid_import?).to be true
          end

          it 'returns false if importer_fields are not present' do
            csv_importer.parser_fields = nil
            expect(subject.valid_import?).to be false
          end
        end

        describe 'Bag or Bags with CSV Metadata' do
          let(:entry) { FactoryBot.create(:bulkrax_csv_entry, importerexporter: csv_importer) }

          before do
            allow(Bulkrax::CsvEntry).to receive_message_chain(:where, :first_or_create!).and_return(entry)
          end

          context 'Bag containing CSV' do
            it 'creates the work entry and increments the counters' do
              expect(subject).to receive(:increment_counters).once
              subject.create_works
            end

            it 'creates the collection entry and increments the counters' do
              expect(subject).to receive(:increment_counters).once
              subject.create_collections
            end

            it 'creates the file_set entry and increments the counters' do
              expect(subject).to receive(:increment_counters).once
              subject.create_file_sets
            end
          end

          context 'Bag with no metadata' do
            it 'Raises an error' do
              csv_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/bag_nometadata"

              subject.create_works
              expect(csv_importer.last_error['error_class']).to eq('StandardError')
            end
          end

          context 'Invalid - not a bag' do
            it 'Raises an error' do
              csv_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/spec/fixtures/bags/not_a_bag"

              subject.create_works
              expect(csv_importer.last_error['error_class']).to eq('StandardError')
            end
          end

          context 'Bag containing folders' do
            before do
              csv_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/bag_of_folders_with_csv"
            end

            it 'creates the collection entry and increments the counters' do
              expect(subject).to receive(:increment_counters).once
              subject.create_collections
            end

            it 'creates the work entry and increments the counters' do
              expect(subject).to receive(:increment_counters).once
              subject.create_works
            end

            it 'creates the file set entry and increments the counters' do
              expect(subject).to receive(:increment_counters).once
              subject.create_file_sets
            end
          end

          context 'Folder containing bags' do
            before do
              csv_importer.parser_fields['import_file_path'] = "./spec/fixtures/bags/folder_of_bags_with_csv"
            end

            it 'creates the collection entry and increments the counters' do
              expect(subject).to receive(:increment_counters).once
              subject.create_collections
            end

            it 'creates the work entry and increments the counters' do
              expect(subject).to receive(:increment_counters).once
              subject.create_works
            end

            it 'creates the file set entry and increments the counters' do
              expect(subject).to receive(:increment_counters).once
              subject.create_file_sets
            end
          end
        end

        describe 'Bag with CSV' do
          let(:entry) { FactoryBot.create(:bulkrax_csv_entry, importerexporter: csv_importer) }

          before do
            allow(Bulkrax::CsvEntry).to receive_message_chain(:where, :first_or_create!).and_return(entry)
          end

          context 'Bag containing CSV' do
            it 'creates the collection entry and increments the counters' do
              expect(subject).to receive(:increment_counters).once
              subject.create_collections
            end

            it 'creates the work entry and increments the counters' do
              expect(subject).to receive(:increment_counters).once
              subject.create_works
            end

            it 'creates the file set entry and increments the counters' do
              expect(subject).to receive(:increment_counters).once
              subject.create_file_sets
            end
          end

          context 'Incorrect metadata filename' do
            before do
              csv_importer.parser_fields['metadata_file_name'] = 'metadata.nt'
            end

            it 'Raises an error' do
              subject.create_works
              expect(csv_importer.last_error['error_class']).to eq('StandardError')
            end
          end
        end

        describe '#path_to_files' do
          context 'when an argument is passed' do
            it 'returns the correct path' do
              expect(subject.path_to_files(filename: 'moon.jpg')).to eq('spec/fixtures/bags/bag_with_csv/data/moon.jpg')
            end
          end
        end
      end
    end

    context 'when exporting a bagit file' do
      # Use OpenStructs to simulate the behavior of ActiveFedora::SolrHit instances.
      subject { described_class.new(exporter) }
      let(:exporter) { FactoryBot.create(:bulkrax_exporter_worktype_bagit) }
      let(:work_ids_solr) { [OpenStruct.new(id: SecureRandom.alphanumeric(9)), OpenStruct.new(id: SecureRandom.alphanumeric(9))] }
      let(:collection_ids_solr) { [OpenStruct.new(id: SecureRandom.alphanumeric(9))] }
      let(:file_set_ids_solr) { [OpenStruct.new(id: SecureRandom.alphanumeric(9)), OpenStruct.new(id: SecureRandom.alphanumeric(9)), OpenStruct.new(id: SecureRandom.alphanumeric(9))] }

      describe '#write_files' do
        let(:work_entry_1) { FactoryBot.create(:bulkrax_csv_entry, importerexporter: exporter) }
        let(:work_entry_2) { FactoryBot.create(:bulkrax_csv_entry, importerexporter: exporter) }
        let(:fileset_entry_1) { FactoryBot.create(:bulkrax_csv_entry_file_set, importerexporter: exporter) }
        let(:fileset_entry_2) { FactoryBot.create(:bulkrax_csv_entry_file_set, importerexporter: exporter) }

        before do
          allow(Bulkrax.persistence_adapter).to receive(:query).and_return(work_ids_solr)
          allow(exporter.entries).to receive(:where).and_return([work_entry_1, work_entry_2, fileset_entry_1, fileset_entry_2])
        end

        it 'attempts to find the related record' do
          expect(ActiveFedora::Base).to receive(:find).with('csv_entry').and_return(nil)

          subject.write_files
        end
      end

      context 'folders and files for export' do
        let(:bulkrax_exporter_run) { FactoryBot.create(:bulkrax_exporter_run, exporter: exporter) }
        let(:site) { instance_double(Site, id: 1, account_id: 1) }
        let(:account) { instance_double(Account, id: 1, name: 'bulkrax') }

        before do
          allow(exporter).to receive(:exporter_runs).and_return([bulkrax_exporter_run])
          allow(Site).to receive(:instance).and_return(site)
          allow(Site.instance).to receive(:account).and_return(account)
        end

        describe '#setup_csv_metadata_export_file' do
          it 'creates the csv metadata file' do
            expect(subject.setup_csv_metadata_export_file(2, '3')).to eq('tmp/exports/1/1/2/3/metadata.csv')
          end
        end

        describe '#setup_triple_metadata_export_file' do
          it 'creates the csv metadata file' do
            expect(subject.setup_triple_metadata_export_file(2, '3')).to eq('tmp/exports/1/1/2/3/metadata.nt')
          end
        end

        describe '#setup_bagit_folder' do
          it 'creates the csv metadata file' do
            expect(subject.setup_bagit_folder(2, '3')).to eq('tmp/exports/1/1/2/3')
          end
        end
      end
    end
  end
end
