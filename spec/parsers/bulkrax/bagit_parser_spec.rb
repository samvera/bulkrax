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
      subject { described_class.new(exporter) }
      let(:exporter) { FactoryBot.create(:bulkrax_exporter_worktype_bagit) }
      let(:work_ids_solr) { [OpenStruct.new(id: SecureRandom.alphanumeric(9)), OpenStruct.new(id: SecureRandom.alphanumeric(9))] }
      let(:collection_ids_solr) { [OpenStruct.new(id: SecureRandom.alphanumeric(9))] }
      let(:file_set_ids_solr) { [OpenStruct.new(id: SecureRandom.alphanumeric(9)), OpenStruct.new(id: SecureRandom.alphanumeric(9)), OpenStruct.new(id: SecureRandom.alphanumeric(9))] }
      let(:parent_record_1) { build(:work) }
      let(:parent_record_2) { build(:another_work) }

      before do
        allow(parent_record_1).to receive(:file_set_ids).and_return([file_set_ids_solr.pluck(:id).first])
        allow(parent_record_1).to receive(:member_of_collection_ids).and_return([collection_ids_solr.first.id])
        allow(parent_record_2).to receive(:file_set_ids).and_return([])
        allow(ActiveFedora::Base).to receive(:find).with(work_ids_solr.first.id).and_return(parent_record_1)
        allow(ActiveFedora::Base).to receive(:find).with(work_ids_solr.last.id).and_return(parent_record_2)
      end

      describe '#find_child_file_sets' do
        before do
          subject.instance_variable_set(:@file_set_ids, [])
        end

        it 'returns the ids when child file sets are present' do
          subject.find_child_file_sets(work_ids_solr.pluck(:id))
          expect(subject.instance_variable_get(:@file_set_ids)).to eq([file_set_ids_solr.pluck(:id).first])
        end
      end

      describe '#create_new_entries' do
        # Use OpenStructs to simulate the behavior of ActiveFedora::SolrHit instances.

        it 'invokes Bulkrax::ExportWorkJob once per Entry' do
          expect(ActiveFedora::SolrService).to receive(:query).and_return(work_ids_solr)
          expect(Bulkrax::ExportWorkJob).to receive(:perform_now).exactly(2).times
          subject.create_new_entries
        end

        context 'with an export limit of 1' do
          let(:exporter) { FactoryBot.create(:bulkrax_exporter_worktype_bagit, limit: 1) }

          it 'invokes Bulkrax::ExportWorkJob once' do
            expect(ActiveFedora::SolrService).to receive(:query).and_return(work_ids_solr)
            expect(Bulkrax::ExportWorkJob).to receive(:perform_now).exactly(1).times
            subject.create_new_entries
          end
        end

        context 'with an export limit of 0' do
          let(:exporter) { FactoryBot.create(:bulkrax_exporter_worktype_bagit, limit: 0) }

          it 'invokes Bulkrax::ExportWorkJob once per Entry' do
            expect(ActiveFedora::SolrService).to receive(:query).and_return(work_ids_solr)
            expect(Bulkrax::ExportWorkJob).to receive(:perform_now).exactly(2).times
            subject.create_new_entries
          end
        end

        context 'when exporting all' do
          let(:exporter) { FactoryBot.create(:bulkrax_exporter, :all) }

          before do
            allow(ActiveFedora::SolrService).to receive(:query).and_return(work_ids_solr, collection_ids_solr, file_set_ids_solr)
            allow(ActiveFedora::Base).to receive(:find).and_return(parent_record_1)
          end

          it 'creates entries for all works, collections and file sets' do
            expect(ExportWorkJob).to receive(:perform_now).exactly(6).times

            subject.create_new_entries
          end

          it 'creates entries for all works' do
            work_entry_ids = Entry.where(identifier: work_ids_solr.map(&:id)).map(&:id)
            work_entry_ids.each do |id|
              expect(ExportWorkJob).to receive(:perform_now).with(id, exporter.last_run.id).once
            end

            subject.create_new_entries
          end

          it 'creates entries for all collections' do
            collection_entry_ids = Entry.where(identifier: collection_ids_solr.map(&:id)).map(&:id)
            collection_entry_ids.each do |id|
              expect(ExportWorkJob).to receive(:perform_now).with(id, exporter.last_run.id).once
            end

            subject.create_new_entries
          end

          it 'creates entries for all file sets' do
            file_set_entry_ids = Entry.where(identifier: file_set_ids_solr.map(&:id)).map(&:id)
            file_set_entry_ids.each do |id|
              expect(ExportWorkJob).to receive(:perform_now).with(id, exporter.last_run.id).once
            end

            subject.create_new_entries
          end

          it 'exported entries are given the correct class' do
            # Bulkrax::CsvFileSetEntry == Bulkrax::CsvEntry (false)
            # Bulkrax::CsvFileSetEntry.is_a? Bulkrax::CsvEntry (true)
            # because of the above, although we only have 2 work id's, the 3 file set id's also increase the Bulkrax::CsvEntry count
            expect { subject.create_new_entries }
              .to change(CsvEntry, :count)
              .by(6)
              .and change(CsvCollectionEntry, :count)
              .by(1)
              .and change(CsvFileSetEntry, :count)
              .by(3)
          end
        end
      end

      describe '#write_files' do
        let(:work_entry_1) { FactoryBot.create(:bulkrax_csv_entry, importerexporter: exporter) }
        let(:work_entry_2) { FactoryBot.create(:bulkrax_csv_entry, importerexporter: exporter) }
        let(:fileset_entry_1) { FactoryBot.create(:bulkrax_csv_entry_file_set, importerexporter: exporter) }
        let(:fileset_entry_2) { FactoryBot.create(:bulkrax_csv_entry_file_set, importerexporter: exporter) }

        before do
          allow(ActiveFedora::SolrService).to receive(:query).and_return(work_ids_solr)
          allow(exporter.entries).to receive(:where).and_return([work_entry_1, work_entry_2, fileset_entry_1, fileset_entry_2])
        end

        it 'attempts to find the related record' do
          expect(ActiveFedora::Base).to receive(:find).with('csv_entry').and_return(nil)

          subject.write_files
        end
      end

      context 'folders and files for export' do
        let(:bulkrax_exporter_run) { FactoryBot.create(:bulkrax_exporter_run, exporter: exporter) }

        before do
          allow(exporter).to receive(:exporter_runs).and_return([bulkrax_exporter_run])
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

      describe '#total' do
        before do
          allow(subject).to receive(:current_record_ids).and_return(work_ids_solr + file_set_ids_solr)
        end

        context 'when there is no limit' do
          it 'counts the correct number of works, collections, and filesets' do
            expect(subject.total).to eq(5)
          end
        end

        context 'when there is a limit' do
          let(:exporter) { FactoryBot.create(:bulkrax_exporter_worktype_bagit, limit: 1) }
          it 'counts the correct number of works, collections, and filesets' do
            expect(subject.total).to eq(1)
          end
        end
      end

      describe '#export_headers' do
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
          allow(subject).to receive(:headers).and_return(entry.parsed_metadata.keys)
        end

        # rubocop:disable RSpec/ExampleLength
        it 'returns an array of single, numerated and double numerated header values' do
          headers = subject.export_headers
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
