# frozen_string_literal: true

require 'rails_helper'
require 'bagit'

module Bulkrax
  RSpec.describe BagitParser do
    describe '#total' do
      context 'while exporting' do
        subject { described_class.new(exporter) }
        let(:exporter) { FactoryBot.create(:bulkrax_exporter_worktype_bagit) }
        let(:bulkrax_exporter_run) { FactoryBot.create(:bulkrax_exporter_run, exporter: exporter) }
        let(:work_ids_solr) { [OpenStruct.new(id: SecureRandom.alphanumeric(9)), OpenStruct.new(id: SecureRandom.alphanumeric(9))] }
        let(:collection_ids_solr) { [OpenStruct.new(id: SecureRandom.alphanumeric(9))] }
        let(:file_set_ids_solr) { [OpenStruct.new(id: SecureRandom.alphanumeric(9)), OpenStruct.new(id: SecureRandom.alphanumeric(9)), OpenStruct.new(id: SecureRandom.alphanumeric(9))] }

        before do
          allow(subject).to receive(:current_record_ids).and_return(work_ids_solr + collection_ids_solr + file_set_ids_solr)
        end

        context 'when there is no limit' do
          it 'counts the correct number of works, collections, and filesets' do
            expect(subject.total).to eq(6)
          end
        end

        context 'when there is a limit' do
          let(:exporter) { FactoryBot.create(:bulkrax_exporter_worktype_bagit, limit: 1) }
          it 'counts the correct number of works, collections, and filesets' do
            expect(subject.total).to eq(1)
          end
        end
      end
    end

    context 'when importing a bagit file' do
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

          it 'returns false if importer_fields are not present' do
            rdf_importer.parser_fields = nil
            expect(subject.valid_import?).to be false
          end
        end

        describe 'Bag or Bags with RDF Metadata' do
          let(:entry) { FactoryBot.create(:bulkrax_rdf_entry, importerexporter: rdf_importer) }
          let(:parser_fields) do
            {
              'metadata_file_name' => 'metadata.nt',
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
              rdf_importer.parser_fields['metadata_file_name'] = 'metadata.nt'
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

          it 'returns false if importer_fields are not present' do
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
              csv_importer.parser_fields['metadata_file_name'] = 'metadata.nt'
            end

            it 'Raises an error' do
              subject.create_works
              expect(csv_importer.last_error['error_class']).to eq('StandardError')
            end
          end
        end
      end
    end

    context 'when exporting a bagit file' do
      subject { described_class.new(exporter) }
      let(:exporter) { FactoryBot.create(:bulkrax_exporter_worktype_bagit) }

      describe '#create_new_entries' do
        subject(:parser) { described_class.new(exporter) }
        # Use OpenStructs to simulate the behavior of ActiveFedora::SolrHit instances.
        let(:work_ids_solr) { [OpenStruct.new(id: SecureRandom.alphanumeric(9)), OpenStruct.new(id: SecureRandom.alphanumeric(9))] }
        let(:collection_ids_solr) { [OpenStruct.new(id: SecureRandom.alphanumeric(9))] }
        let(:file_set_ids_solr) { [OpenStruct.new(id: SecureRandom.alphanumeric(9)), OpenStruct.new(id: SecureRandom.alphanumeric(9)), OpenStruct.new(id: SecureRandom.alphanumeric(9))] }

        it 'invokes Bulkrax::ExportWorkJob once per Entry' do
          expect(ActiveFedora::SolrService).to receive(:query).and_return(work_ids_solr)
          expect(Bulkrax::ExportWorkJob).to receive(:perform_now).exactly(2).times
          parser.create_new_entries
        end

        context 'with an export limit of 1' do
          let(:exporter) { FactoryBot.create(:bulkrax_exporter_worktype_bagit, limit: 1) }

          it 'invokes Bulkrax::ExportWorkJob once' do
            expect(ActiveFedora::SolrService).to receive(:query).and_return(work_ids_solr)
            expect(Bulkrax::ExportWorkJob).to receive(:perform_now).exactly(1).times
            parser.create_new_entries
          end
        end

        context 'with an export limit of 0' do
          let(:exporter) { FactoryBot.create(:bulkrax_exporter_worktype_bagit, limit: 0) }

          it 'invokes Bulkrax::ExportWorkJob once per Entry' do
            expect(ActiveFedora::SolrService).to receive(:query).and_return(work_ids_solr)
            expect(Bulkrax::ExportWorkJob).to receive(:perform_now).exactly(2).times
            parser.create_new_entries
          end
        end

        context 'when exporting all' do
          let(:exporter) { FactoryBot.create(:bulkrax_exporter, :all) }

          before do
            allow(ActiveFedora::SolrService).to receive(:query).and_return(work_ids_solr, file_set_ids_solr)
          end

          it 'exports works, and file sets' do
            expect(ExportWorkJob).to receive(:perform_now).exactly(5).times

            parser.create_new_entries
          end

          it 'exports all works' do
            work_entry_ids = Entry.where(identifier: work_ids_solr.map(&:id)).map(&:id)
            work_entry_ids.each do |id|
              expect(ExportWorkJob).to receive(:perform_now).with(id, exporter.last_run.id).once
            end

            parser.create_new_entries
          end

          it 'exports all file sets' do
            file_set_entry_ids = Entry.where(identifier: file_set_ids_solr.map(&:id)).map(&:id)
            file_set_entry_ids.each do |id|
              expect(ExportWorkJob).to receive(:perform_now).with(id, exporter.last_run.id).once
            end

            parser.create_new_entries
          end

          it 'exported entries are given the correct class' do
            # Bulkrax::CsvFileSetEntry == Bulkrax::CsvEntry (false)
            # Bulkrax::CsvFileSetEntry.is_a? Bulkrax::CsvEntry (true)
            # because of the above, although we only have 2 work id's, the 3 file set id's also increase the Bulkrax::CsvEntry count
            expect { parser.create_new_entries }
              .to change(CsvEntry, :count)
              .by(5)
              .and change(CsvFileSetEntry, :count)
              .by(3)
          end
        end
      end

      describe '#export_headers' do
        subject(:parser) { described_class.new(exporter) }
        let(:work_id) { SecureRandom.alphanumeric(9) }
        let(:exporter) do
          FactoryBot.create(:bulkrax_exporter_worktype_bagit, field_mapping: {
                              'id' => { from: ['id'], source_identifier: true },
                              'title' => { from: ['display_title'] },
                              'first_name' => { from: ['multiple_objects_first_name'], object: 'multiple_objects' },
                              'last_name' => { from: ['multiple_objects_last_name'], object: 'multiple_objects' },
                              'position' => { from: ['multiple_objects_position'], object: 'multiple_objects', nested_type: 'Array' }
                            })
        end

        let(:entry) do
          FactoryBot.create(:bulkrax_csv_entry, importerexporter: exporter, parsed_metadata: {
                              'id' => work_id,
                              'display_title' => 'First',
                              'multiple_objects_first_name_1' => 'Judge',
                              'multiple_objects_last_name_1' => 'Hines',
                              'multiple_objects_position_1_1' => 'King',
                              'multiple_objects_position_1_2' => 'Lord',
                              'multiple_objects_first_name_2' => 'Aaliyah'
                            })
        end

        before do
          allow(ActiveFedora::SolrService).to receive(:query).and_return(OpenStruct.new(id: work_id))
          allow(exporter.entries).to receive(:where).and_return([entry])
          allow(parser).to receive(:headers).and_return(entry.parsed_metadata.keys)
        end

        # rubocop:disable RSpec/ExampleLength
        it 'returns an array of single, numerated and double numerated header values' do
          headers = parser.export_headers
          expect(headers).to include('id')
          expect(headers).to include('model')
          expect(headers).to include('display_title')
          expect(headers).to include('multiple_objects_first_name_1')
          expect(headers).to include('multiple_objects_last_name_1')
          expect(headers).to include('multiple_objects_position_1_1')
          expect(headers).to include('multiple_objects_position_1_2')
          expect(headers).to include('multiple_objects_first_name_2')
        end
        # rubocop:enable RSpec/ExampleLength
      end
    end
  end
end
