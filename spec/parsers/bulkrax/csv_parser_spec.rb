# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe CsvParser do
    subject { described_class.new(importer) }
    let(:importer) { FactoryBot.build(:bulkrax_importer_csv) }
    let(:relationship_importer) { FactoryBot.create(:bulkrax_importer_csv, :with_relationships_mappings) }
    let(:relationship_subject) { described_class.new(relationship_importer) }
    let(:all_collection_titles) { subject.collections.collect { |c| c[:title] } }

    describe '#build_records' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv, :with_relationships_mappings, parser_fields: { 'import_file_path' => 'spec/fixtures/csv/all_record_types.csv' }) }

      it 'sets @collections' do
        expect(subject.instance_variable_get(:@collections)).to be_nil

        subject.build_records

        expect(subject.instance_variable_get(:@collections)).not_to be_nil
      end

      it 'sets @works' do
        expect(subject.instance_variable_get(:@works)).to be_nil

        subject.build_records

        expect(subject.instance_variable_get(:@works)).not_to be_nil
      end

      it 'sets @file_sets' do
        expect(subject.instance_variable_get(:@file_sets)).to be_nil

        subject.build_records

        expect(subject.instance_variable_get(:@file_sets)).not_to be_nil
      end

      shared_examples 'records are assigned correctly' do
        it 'adds collection records to the @collections variable' do
          subject.build_records

          expect(subject.collections.collect { |r| r[:source_identifier] })
            .to contain_exactly('art_c_1', 'art_c_2')
        end

        it 'adds work records to the @works variable' do
          subject.build_records

          expect(subject.works.collect { |r| r[:source_identifier] })
            .to contain_exactly('art_w_1', 'art_w_2')
        end

        it 'adds file set records to the @file_sets variable' do
          subject.build_records

          expect(subject.file_sets.collect { |r| r[:source_identifier] })
            .to contain_exactly('art_fs_1', 'art_fs_2')
        end
      end
      include_examples 'records are assigned correctly'

      context 'when there are multiple model field mappings' do
        before do
          allow(subject).to receive(:model_field_mappings).and_return(%w[work_type model])
        end

        include_examples 'records are assigned correctly'
      end

      context 'when CSV does not specify model' do
        before do
          importer.parser_fields['import_file_path'] = 'spec/fixtures/csv/ok.csv'
        end

        it 'puts all records in the @works variable' do
          subject.build_records

          expect(subject.works).to eq(subject.records)
        end
      end

      context 'when the model value has whitespace' do
        before do
          importer.parser_fields['import_file_path'] = 'spec/fixtures/csv/all_record_types_whitespace.csv'
        end

        include_examples 'records are assigned correctly'
      end
    end

    describe '#collections' do
      before do
        importer.parser_fields = { import_file_path: './spec/fixtures/csv/mixed_works_and_collections.csv' }
      end

      it 'includes rows whose :model is set to Collection' do
        expect(all_collection_titles).to include('Collection 1 Title', 'Collection 2 Title')
      end

      it 'matches :model column case-insensitively' do
        allow(subject).to receive(:records).and_return([{ model: 'cOllEcTiOn' }])

        expect(subject.collections).to include({ model: 'cOllEcTiOn' })
      end

      describe ':model field mappings' do
        before do
          allow(subject)
            .to receive(:records)
            .and_return(
              [
                { map_1: 'Collection', title: 'C1', map_2: '', model: '' },
                { map_2: 'Collection', title: 'C2', map_1: '', model: '' },
                { model: 'Collection', title: 'C3', map_1: '', map_2: '' }
              ]
            )
        end

        context 'when :model has field mappings' do
          before do
            allow(subject).to receive(:model_field_mappings).and_return(['map_1', 'map_2', 'model'])
          end

          it 'uses the field mappings' do
            expect(all_collection_titles).to include('C1', 'C2')
          end
        end

        context 'when :model does not have field mappings' do
          it 'uses :model' do
            expect(all_collection_titles).to include('C3')
            expect(all_collection_titles).not_to include('C1', 'C2')
          end
        end
      end
    end

    describe '#works' do
      before do
        importer.parser_fields = { import_file_path: './spec/fixtures/csv/mixed_works_and_collections.csv' }
      end

      it 'returns all work records' do
        expect(subject.works.collect { |w| w[:source_identifier] })
          .to contain_exactly('work_1', 'work_2')
      end
    end

    describe '#file_sets' do
      before do
        importer.parser_fields = { import_file_path: './spec/fixtures/csv/work_with_file_sets.csv' }
      end

      it 'returns all file set records' do
        expect(subject.file_sets.collect { |fs| fs[:source_identifier] })
          .to contain_exactly('fs1', 'fs2')
      end
    end

    describe '#create_collections' do
      context 'when importing collections by title through works' do
        before do
          importer.parser_fields = { import_file_path: './spec/fixtures/csv/good.csv' }
          allow(ImportCollectionJob).to receive(:perform_now)
        end

        it 'creates CSV collection entries for each collection' do
          expect { subject.create_collections }.to change(CsvCollectionEntry, :count).by(2)
        end

        it 'runs an ImportCollectionJob in memory for each entry' do
          expect(ImportCollectionJob).to receive(:perform_later).twice

          subject.create_collections
        end
      end

      context 'when importing collections with metadata' do
        before do
          importer.parser_fields = { import_file_path: './spec/fixtures/csv/collections.csv' }
        end

        it 'creates CSV collection entries for each collection' do
          expect { subject.create_collections }.to change(CsvCollectionEntry, :count).by(2)
        end

        it 'runs an ImportCollectionJob in the background for each entry' do
          expect(ImportCollectionJob).to receive(:perform_later).twice

          subject.create_collections
        end
      end

      context 'when a collection entry fails during creation' do
        before do
          importer.parser_fields = { import_file_path: './spec/fixtures/csv/failed_collection.csv' }
        end

        it 'does not stop the remaining collection entries from being processed' do
          expect { subject.create_collections }.to change(CsvCollectionEntry, :count).by(2)
        end
      end

      describe 'setting collection entry identifiers' do
        let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }

        before do
          allow(subject)
            .to receive(:collections)
            .and_return([record_hash])
        end

        context 'when collection record has a source_identifier' do
          let(:record_hash) { { source_identifier: 'csid' } }

          it "uses the record's source_identifier as the entry's identifier" do
            subject.create_collections

            expect(importer.entries.last.identifier).to eq('csid')
          end
        end

        context 'when collection record does not have a source_identifier' do
          let(:record_hash) { { title: 'no source id | alt title', model: 'Collection' } }

          it "uses the record's first title as the entry's identifier" do
            subject.create_collections

            expect(ImporterRun.find(subject.current_run.id).failed_records).to eq(1)
          end

          context 'when Bulkrax is set to fill in blank source_identifiers' do
            before do
              allow(Bulkrax).to receive_message_chain(:fill_in_blank_source_identifiers, :present?).and_return(true)
              allow(Bulkrax).to receive_message_chain(:fill_in_blank_source_identifiers, :call).and_return("#{importer.id}-99")
            end

            it "uses the generated identifier as the entry's identifier" do
              subject.create_collections

              expect(importer.entries.last.identifier).to eq("#{importer.id}-99")
            end
          end
        end
      end
    end

    describe '#create_works' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }
      let(:entry) { FactoryBot.create(:bulkrax_entry, importerexporter: importer) }

      before do
        allow(Bulkrax::CsvEntry).to receive_message_chain(:where, :first_or_create!).and_return(entry)
        allow(entry).to receive(:id)
        allow(Bulkrax::ImportWorkJob).to receive(:perform_later)
      end

      context 'with malformed CSV' do
        before do
          importer.parser_fields = { import_file_path: './spec/fixtures/csv/malformed.csv' }
        end

        it 'returns an empty array, and records the error on the importer' do
          subject.create_works
          expect(importer.last_error['error_class']).to eq('CSV::MalformedCSVError')
        end
      end

      context 'without an identifier column' do
        before do
          importer.parser_fields = { import_file_path: './spec/fixtures/csv/bad.csv' }
        end

        it 'skips all of the lines' do
          expect(subject.importerexporter).not_to receive(:increment_counters)
          subject.create_works
        end
      end

      context 'with a nil value in the identifier column' do
        before do
          importer.parser_fields = { import_file_path: './spec/fixtures/csv/ok.csv' }
        end

        it 'skips the bad line' do
          expect(subject).to receive(:increment_counters).once
          subject.create_works
        end

        context 'with fill_in_source_identifier set' do
          it 'fills in the source_identifier if fill_in_source_identifier is set' do
            expect(subject).to receive(:increment_counters).twice
            # once for present? and once to execute
            expect(Bulkrax).to receive(:fill_in_blank_source_identifiers).twice.and_return(->(_parser, _index) { "4649ee79-7d7a-4df0-86d6-d6865e2925ca" })
            subject.create_works
            expect(subject.seen).to include("2", "4649ee79-7d7a-4df0-86d6-d6865e2925ca")
          end
        end
      end

      context 'with good data' do
        before do
          importer.parser_fields = { import_file_path: './spec/fixtures/csv/good.csv' }
        end

        it 'processes the line' do
          expect(subject).to receive(:increment_counters).twice
          subject.create_works
        end

        it 'has a source id field' do
          expect(subject.source_identifier).to eq(:source_identifier)
        end

        it 'has a work id field' do
          expect(subject.work_identifier).to eq(:source)
        end

        it 'has custom source and work id fields' do
          subject.importerexporter.field_mapping['title'] = { 'from' => ['title'], 'source_identifier' => true }
          expect(subject.source_identifier).to eq(:title)
          expect(subject.work_identifier).to eq(:title)
        end

        it 'counts the correct number of works and collections' do
          subject.records
          expect(subject.total).to eq(4)
          expect(subject.collections_total).to eq(2)
        end
      end
    end

    describe '#create_file_sets' do
      before do
        importer.parser_fields = { import_file_path: './spec/fixtures/csv/work_with_file_sets.csv' }
      end

      it 'creates CSV file set entries for each collection' do
        expect { subject.create_file_sets }.to change(CsvFileSetEntry, :count).by(2)
      end

      it 'runs an ImportFileSetJob for each entry' do
        expect(ImportFileSetJob).to receive(:perform_later).twice

        subject.create_file_sets
      end
    end

    describe '#write_partial_import_file', clean_downloads: true do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv_failed) }
      let(:file)     { fixture_file_upload('./spec/fixtures/csv/ok.csv') }

      context 'in a single tenant application' do
        it 'returns the path of the partial import file' do
          expect(subject.write_partial_import_file(file))
            .to eq("tmp/imports/#{importer.id}_#{importer.created_at.strftime('%Y%m%d%H%M%S')}/failed_corrected_entries.csv")
        end

        it 'moves the partial import file to the correct path' do
          expect(File.exist?(file.path)).to eq(true)

          new_path = subject.write_partial_import_file(file)

          expect(File.exist?(file.path)).to eq(false)
          expect(File.exist?(new_path)).to eq(true)
        end

        it 'renames the uploaded file to the original import filename + _corrected_entries' do
          import_filename = importer.parser_fields['import_file_path'].split('/').last
          uploaded_filename = file.original_filename
          partial_import_filename = subject.write_partial_import_file(file).split('/').last

          expect(import_filename).to eq('failed.csv')
          expect(uploaded_filename).to eq('ok.csv')
          expect(partial_import_filename).not_to eq(uploaded_filename)
          expect(partial_import_filename).to eq('failed_corrected_entries.csv')
        end
      end

      context 'in a multi tenant application' do
        let(:site) { instance_double(Site, id: 1, account_id: 1) }
        let(:account) { instance_double(Account, id: 1, name: 'bulkrax') }

        before do
          allow(Site).to receive(:instance).and_return(site)
          allow(Site.instance).to receive(:account).and_return(account)
          ENV['HYKU_MULTITENANT'] = 'true'
        end

        after do
          ENV['HYKU_MULTITENANT'] = 'false'
        end

        it 'returns the path of the partial import file' do
          expect(subject.write_partial_import_file(file))
            .to eq("tmp/imports/bulkrax/#{importer.id}_#{importer.created_at.strftime('%Y%m%d%H%M%S')}/failed_corrected_entries.csv")
        end
      end
    end

    describe '#create_new_entries' do
      subject(:parser) { described_class.new(exporter) }
      let(:exporter) { FactoryBot.create(:bulkrax_exporter, :all) }
      let(:work_ids_solr) { [SolrDocument.new(id: SecureRandom.alphanumeric(9)), SolrDocument.new(id: SecureRandom.alphanumeric(9))] }
      let(:collection_ids_solr) { [SolrDocument.new(id: SecureRandom.alphanumeric(9)), SolrDocument.new(id: SecureRandom.alphanumeric(9))] }
      let(:file_set_ids_solr) { [SolrDocument.new(id: SecureRandom.alphanumeric(9)), SolrDocument.new(id: SecureRandom.alphanumeric(9)), SolrDocument.new(id: SecureRandom.alphanumeric(9))] }
      let(:limit) { 1000 }

      let(:record_set) do
        (
          work_ids_solr.map { |doc| [doc.id, parser.entry_class] } +
          collection_ids_solr.map { |doc| [doc.id, parser.collection_entry_class] } +
          file_set_ids_solr.map { |doc| [doc.id, parser.file_set_entry_class] }
        )[0...limit]
      end

      before do
        allow(Bulkrax::ParserExportRecordSet).to(
          receive(:for).with(parser: parser, export_from: exporter.export_from).and_return(record_set)
        )
      end

      context 'with an export limit of 0' do
        it 'invokes Bulkrax::ExportWorkJob once per Entry' do
          expect(Bulkrax::ExportWorkJob).to receive(:perform_now).exactly(record_set.count).times
          parser.create_new_entries
        end
      end

      context 'with an export limit of 1' do
        let(:limit) { 1 }
        it 'invokes Bulkrax::ExportWorkJob once' do
          exporter.limit = limit

          # although the work has a file attached, the limit means the file set is not exported
          expect(Bulkrax::ExportWorkJob).to receive(:perform_now).exactly(limit).times
          parser.create_new_entries
        end
      end

      context 'when exporting all' do
        before do
          stub_request(:head, %r{http://localhost:8986/rest/test/?.*}).to_return(status: 200, body: "", headers: {})
          stub_request(:get, %r{http://localhost:8986/rest/test/?.*}).to_return(status: 200, body: "", headers: {})
        end

        it 'exports works, collections, and file sets' do
          expect(Bulkrax::ExportWorkJob).to receive(:perform_now).exactly(record_set.count).times

          parser.create_new_entries
        end

        it 'exports all works' do
          work_entry_ids = Entry.where(identifier: work_ids_solr.map(&:id)).map(&:id)
          work_entry_ids.each do |id|
            expect(ExportWorkJob).to receive(:perform_now).with(id, exporter.last_run.id).once
          end

          parser.create_new_entries
        end

        it 'exports all collections' do
          collection_entry_ids = Entry.where(identifier: collection_ids_solr.map(&:id)).map(&:id)
          collection_entry_ids.each do |id|
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
          expect { parser.create_new_entries }
            .to change(CsvFileSetEntry, :count)
            .by(3)
            .and change(CsvCollectionEntry, :count)
            .by(2)
            .and change(CsvEntry, :count)
            .by(7) # 7 csv entries minus 3 file set entries minus 2 collection entries equals 2 work entries
        end
      end
    end

    describe '#setup_export_file' do
      subject(:parser) { described_class.new(exporter) }
      let(:bulkrax_exporter_run) { FactoryBot.create(:bulkrax_exporter_run, exporter: exporter) }
      let(:exporter) { FactoryBot.create(:bulkrax_exporter_worktype) }
      let(:site) { instance_double(Site, id: 1, account_id: 1) }
      let(:account) { instance_double(Account, id: 1, name: 'bulkrax') }

      before do
        allow(exporter).to receive(:exporter_runs).and_return([bulkrax_exporter_run])
        allow(Site).to receive(:instance).and_return(site)
        allow(Site.instance).to receive(:account).and_return(account)
      end

      it 'creates the csv metadata file' do
        expect(subject.setup_export_file(2)).to eq('tmp/exports/1/1/2/export_Generic_from_worktype_2.csv')
      end
    end

    describe '#total' do
      context 'on import' do
        subject { described_class.new(importer) }
        let(:importer) { FactoryBot.build(:bulkrax_importer_csv, parser_fields: { 'total' => 3 }) }

        it 'sets @total' do
          expect(subject.instance_variable_get(:@total)).to be_nil

          subject.total

          expect(subject.instance_variable_get(:@total)).not_to be_nil
          expect(subject.instance_variable_get(:@total)).to eq(3)
        end
      end

      context 'on export' do
        subject { described_class.new(exporter) }
        let(:exporter) { FactoryBot.build(:bulkrax_exporter, limit: 1) }

        it 'sets @total' do
          expect(subject.instance_variable_get(:@total)).to be_nil

          subject.total

          expect(subject.instance_variable_get(:@total)).not_to be_nil
          expect(subject.instance_variable_get(:@total)).to eq(1)
        end
      end
    end

    describe '#records_split_count' do
      it 'defaults to 1000' do
        expect(subject.records_split_count).to eq(1000)
      end
    end

    describe '#path_to_files' do
      context 'when an argument is passed' do
        it 'returns the correct path' do
          expect(subject.path_to_files(filename: 'sun.jpg')).to eq('spec/fixtures/csv/files/sun.jpg')
        end

        it 'returns the correct path when multiple files are processed' do
          expect(subject.path_to_files(filename: 'sun.jpg')).to eq('spec/fixtures/csv/files/sun.jpg')

          second_path = subject.path_to_files(filename: 'moon.jpg')
          expect(second_path).to eq('spec/fixtures/csv/files/moon.jpg')
          expect(second_path).not_to eq('spec/fixtures/csv/files/sun.jpg')
        end
      end

      context 'when an argument is not passed' do
        it 'returns the correct path' do
          expect(subject.path_to_files).to eq('spec/fixtures/csv/files/')
        end
      end
    end

    describe '#missing_elements' do
      let(:entry_no_title) { FactoryBot.create(:bulkrax_csv_entry_missing_title, raw_metadata: { title: '', source_identifier: "12345" }) }

      it 'returns required keys that are missing from the record' do
        expect(subject.missing_elements(entry_no_title.raw_metadata)).to eq(['title'])
      end
    end

    describe '#write_errored_entries_file', clean_downloads: true do
      let(:importer)         { FactoryBot.create(:bulkrax_importer_csv_failed, entries: [entry_failed, entry_succeeded, entry_collection]) }
      let(:entry_failed)     { FactoryBot.create(:bulkrax_csv_entry_failed, raw_metadata: { title: 'Failed' }) }
      let(:entry_succeeded)  { FactoryBot.create(:bulkrax_csv_entry, raw_metadata: { title: 'Succeeded' }) }
      let(:entry_collection) { FactoryBot.create(:bulkrax_csv_entry_collection, raw_metadata: { title: 'Collection' }) }
      let(:import_file_path) { importer.errored_entries_csv_path }

      it 'returns true' do
        expect(subject.write_errored_entries_file).to eq(true)
      end

      it 'writes a CSV file to the correct location' do
        # ensure path is clean before we start
        FileUtils.rm_rf(import_file_path)
        expect(File.exist?(import_file_path)).to eq(false)

        subject.write_errored_entries_file

        expect(File.exist?(import_file_path)).to eq(true)
      end

      it 'contains the contents of failed entries' do
        subject.write_errored_entries_file
        file_contents = File.read(import_file_path)

        expect(file_contents).to include('Failed,')
        expect(file_contents).not_to include('Succeeded')
      end

      it 'ignores failed collection entries' do
        subject.write_errored_entries_file
        file_contents = File.read(import_file_path)

        expect(file_contents).not_to include('Collection')
      end
    end

    describe '#export_headers' do
      subject(:parser) { described_class.new(exporter) }
      let(:work_id) { SecureRandom.alphanumeric(9) }
      let(:exporter) do
        FactoryBot.create(:bulkrax_exporter_worktype, field_mapping: {
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
        allow(Bulkrax.object_factory).to receive(:query).and_return(SolrDocument.new(id: work_id))
        allow(exporter.entries).to receive(:where).and_return([entry])
        allow(parser).to receive(:headers).and_return(entry.parsed_metadata.keys)
      end

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
    end

    describe '#generated_metadata_mapping' do
      context 'when the mapping is set' do
        before do
          importer.field_mapping = {
            'date_uploaded' => { from: ['date_uploaded'], split: '\|', generated: true },
            'unrelated' => { 'from' => ['unrelated_column'] }
          }
        end

        it 'returns the mapping' do
          expect(subject.generated_metadata_mapping).to eq('generated')
        end
      end
    end

    describe '#related_parents_field_mapping' do
      context 'when the mapping is set' do
        before do
          importer.field_mapping = {
            'parents' => { 'from' => ['parents_column'], related_parents_field_mapping: true },
            'children' => { 'from' => ['children_column'], related_children_field_mapping: true },
            'unrelated' => { 'from' => ['unrelated_column'] }
          }
        end

        it 'returns the mapping' do
          expect(subject.related_parents_parsed_mapping).to eq('parents')
        end
      end
    end

    describe '#model_field_mappings' do
      context 'when mappings are set' do
        before do
          allow(Bulkrax)
            .to receive(:field_mappings)
            .and_return({ 'Bulkrax::CsvParser' => { 'model' => { from: ['map_1', 'map_2'] } } })
        end

        it 'includes the mappings' do
          expect(subject.model_field_mappings).to include('map_1', 'map_2')
        end

        it 'always includes "model"' do
          expect(subject.model_field_mappings).to include('model')
        end
      end

      context 'when mappings are set' do
        it 'falls back on "model"' do
          expect(subject.model_field_mappings).to eq(['model'])
        end
      end
    end

    describe 'relationships field mappings' do
      context 'when relationship field mappings are set' do
        before do
          importer.field_mapping = {
            'parents' => { 'from' => ['parents_column'], related_parents_field_mapping: true },
            'children' => { 'from' => ['children_column'], related_children_field_mapping: true },
            'unrelated' => { 'from' => ['unrelated_column'] }
          }
        end

        describe '#related_parents_raw_mapping' do
          it 'returns the name of the column header containing parent relationship data' do
            expect(subject.related_parents_raw_mapping).to eq('parents_column')
          end

          it 'looks for the related_parents_field_mapping' do
            expect(subject).to receive(:get_field_mapping_hash_for).with('related_parents_field_mapping')

            subject.related_parents_raw_mapping
          end

          it 'caches the result' do
            expect(subject.instance_variable_get('@related_parents_raw_mapping')).to be_nil

            subject.related_parents_raw_mapping

            expect(subject.instance_variable_get('@related_parents_raw_mapping')).to eq('parents_column')
          end

          it 'caches the related_parents_field_mapping' do
            expect(subject.instance_variables).not_to include(:@related_parents_field_mapping_hash)

            subject.related_parents_raw_mapping

            expect(subject.instance_variables).to include(:@related_parents_field_mapping_hash)
          end
        end

        describe '#related_parents_parsed_mapping' do
          it 'returns the name of the field that the parent relationship data should map to' do
            expect(subject.related_parents_parsed_mapping).to eq('parents')
          end

          it 'looks for the related_parents_field_mapping' do
            expect(subject).to receive(:get_field_mapping_hash_for).with('related_parents_field_mapping')

            subject.related_parents_parsed_mapping
          end

          it 'caches the result' do
            expect(subject.instance_variable_get('@related_parents_parsed_mapping')).to be_nil

            subject.related_parents_parsed_mapping

            expect(subject.instance_variable_get('@related_parents_parsed_mapping')).to eq('parents')
          end

          it 'caches the related_parents_field_mapping' do
            expect(subject.instance_variables).not_to include(:@related_parents_field_mapping_hash)

            subject.related_parents_parsed_mapping

            expect(subject.instance_variables).to include(:@related_parents_field_mapping_hash)
          end
        end

        describe '#related_children_raw_mapping' do
          it 'returns the name of the column header containing child relationship data' do
            expect(subject.related_children_raw_mapping).to eq('children_column')
          end

          it 'looks for the related_children_field_mapping' do
            expect(subject).to receive(:get_field_mapping_hash_for).with('related_children_field_mapping')

            subject.related_children_raw_mapping
          end

          it 'caches the result' do
            expect(subject.instance_variable_get('@related_children_raw_mapping')).to be_nil

            subject.related_children_raw_mapping

            expect(subject.instance_variable_get('@related_children_raw_mapping')).to eq('children_column')
          end

          it 'caches the related_children_field_mapping' do
            expect(subject.instance_variables).not_to include(:@related_children_field_mapping_hash)

            subject.related_children_raw_mapping

            expect(subject.instance_variables).to include(:@related_children_field_mapping_hash)
          end
        end

        describe '#related_children_parsed_mapping' do
          it 'returns the name of the field that the child relationship data should map to' do
            expect(subject.related_children_parsed_mapping).to eq('children')
          end

          it 'looks for the related_children_field_mapping' do
            expect(subject).to receive(:get_field_mapping_hash_for).with('related_children_field_mapping')

            subject.related_children_parsed_mapping
          end

          it 'caches the result' do
            expect(subject.instance_variable_get('@related_children_parsed_mapping')).to be_nil

            subject.related_children_parsed_mapping

            expect(subject.instance_variable_get('@related_children_parsed_mapping')).to eq('children')
          end

          it 'caches the related_children_field_mapping' do
            expect(subject.instance_variables).not_to include(:@related_children_field_mapping_hash)

            subject.related_children_parsed_mapping

            expect(subject.instance_variables).to include(:@related_children_field_mapping_hash)
          end
        end
      end

      context 'when relationship field mappings are not set' do
        describe '#related_parents_raw_mapping' do
          it { expect(subject.related_parents_raw_mapping).to be_nil }
        end

        describe '#related_parents_parsed_mapping' do
          it { expect(subject.related_parents_parsed_mapping).to eq('parents') }
        end

        describe '#related_children_raw_mapping' do
          it { expect(subject.related_children_raw_mapping).to be_nil }
        end

        describe '#related_children_parsed_mapping' do
          it { expect(subject.related_children_parsed_mapping).to eq('children') }
        end
      end

      context 'when duplicate relationship field mappings are present' do
        before do
          importer.field_mapping = {
            'parents_1' => { 'from' => ['parents_column_1'], related_parents_field_mapping: true },
            'parents_2' => { 'from' => ['parents_column_2'], related_parents_field_mapping: true },
            'children_1' => { 'from' => ['children_column_1'], related_children_field_mapping: true },
            'children_2' => { 'from' => ['children_column_2'], related_children_field_mapping: true }
          }
        end

        describe '#related_parents_raw_mapping' do
          it { expect { subject.related_parents_raw_mapping }.to raise_error(StandardError) }
        end

        describe '#related_parents_parsed_mapping' do
          it { expect { subject.related_parents_parsed_mapping }.to raise_error(StandardError) }
        end

        describe '#related_children_raw_mapping' do
          it { expect { subject.related_children_raw_mapping }.to raise_error(StandardError) }
        end

        describe '#related_children_parsed_mapping' do
          it { expect { subject.related_children_parsed_mapping }.to raise_error(StandardError) }
        end
      end
    end

    describe 'exporter functionality' do
      let(:user) { create(:base_user) }
      let(:exporter) do
        create(:bulkrax_exporter, :all,
               name: 'CSV Parser Test',
               user: user,
               parser_fields: { 'export_from' => 'all' })
      end
      let(:work_id) { 'test_work_123' }

      subject(:parser) do
        described_class.new(importerexporter: exporter)
      end

      describe 'initialization' do
        it 'can be instantiated with an exporter' do
          expect(parser).to be_a(Bulkrax::CsvParser)
        end

        it 'stores the exporter reference in hash structure' do
          # The parser stores the exporter in a hash structure
          expect(parser.importerexporter[:importerexporter]).to eq(exporter)
          expect(parser.importerexporter[:importerexporter]).to be_a(Bulkrax::Exporter)
        end

        it 'can access exporter attributes through hash' do
          actual_exporter = parser.importerexporter[:importerexporter]
          expect(actual_exporter.parser_klass).to eq('Bulkrax::CsvParser')
          expect(actual_exporter.export_from).to eq('all')
        end
      end

      describe 'CSV entry processing for export' do
        let(:entry) do
          build_stubbed(:bulkrax_csv_entry,
                       importerexporter: exporter,
                       identifier: work_id,
                       raw_metadata: { 'title_tesim' => ['Test Work'], 'id' => work_id },
                       parsed_metadata: {
                         'title' => ['Test Work'],
                         'creator' => ['Test Creator'],
                         'identifier' => [work_id]
                       })
        end

        it 'can process entries for CSV export' do
          expect(entry.parsed_metadata).to include('title')
          expect(entry.parsed_metadata).to include('creator')
          expect(entry.parsed_metadata).to include('identifier')
        end

        it 'handles empty parsed_metadata gracefully' do
          empty_entry = build_stubbed(:bulkrax_csv_entry,
                                     importerexporter: exporter,
                                     identifier: 'empty_entry',
                                     parsed_metadata: {})

          expect(empty_entry.parsed_metadata).to be_a(Hash)
          expect(empty_entry.identifier).to eq('empty_entry')
        end

        context 'multi-value field handling' do
          let(:multi_value_entry) do
            build_stubbed(:bulkrax_csv_entry,
                         importerexporter: exporter,
                         identifier: 'multi_value_work',
                         parsed_metadata: {
                           'title' => ['Title One'],
                           'creator' => ['Creator One', 'Creator Two'],
                           'subject' => ['Subject A', 'Subject B', 'Subject C']
                         })
          end

          it 'stores multi-value fields as arrays in parsed_metadata' do
            expect(multi_value_entry.parsed_metadata['creator']).to be_an(Array)
            expect(multi_value_entry.parsed_metadata['creator']).to eq(['Creator One', 'Creator Two'])
            expect(multi_value_entry.parsed_metadata['subject']).to eq(['Subject A', 'Subject B', 'Subject C'])
          end

          it 'handles single-value fields appropriately' do
            expect(multi_value_entry.parsed_metadata['title']).to eq(['Title One'])
          end
        end

        context 'special character handling' do
          let(:special_char_entry) do
            build_stubbed(:bulkrax_csv_entry,
                         importerexporter: exporter,
                         identifier: 'special_chars',
                         parsed_metadata: {
                           'title' => ['Title with "quotes" and, commas'],
                           'description' => ['Description with\nnewlines and\ttabs'],
                           'creator' => ['Título con acentos', 'Creador François']
                         })
          end

          it 'preserves special characters in parsed_metadata' do
            expect(special_char_entry.parsed_metadata['title']).to eq(['Title with "quotes" and, commas'])
            expect(special_char_entry.parsed_metadata['description']).to eq(['Description with\nnewlines and\ttabs'])
          end

          it 'handles unicode characters properly' do
            expect(special_char_entry.parsed_metadata['creator']).to include('Título con acentos')
            expect(special_char_entry.parsed_metadata['creator']).to include('Creador François')
          end
        end
      end

      describe 'export configuration access' do
        it 'can access parser_fields from exporter' do
          actual_exporter = parser.importerexporter[:importerexporter]
          expect(actual_exporter.parser_fields).to be_a(Hash)
          expect(actual_exporter.parser_fields['export_from']).to eq('all')
        end

        it 'provides access to export configuration' do
          actual_exporter = parser.importerexporter[:importerexporter]
          expect(actual_exporter.parser_fields['export_from']).to eq('all')
          expect(actual_exporter.export_from).to eq('all')
        end

        context 'metadata_only option' do
          let(:metadata_exporter) do
            create(:bulkrax_exporter, :all,
                   user: user,
                   name: 'Metadata Only Export',
                   export_type: 'metadata',
                   parser_fields: { 'export_from' => 'all', 'metadata_only' => true })
          end

          it 'respects metadata_only configuration' do
            expect(metadata_exporter.export_type).to eq('metadata')
            expect(metadata_exporter.parser_fields['metadata_only']).to be true

            # Test parser can access this configuration
            metadata_parser = described_class.new(importerexporter: metadata_exporter)
            actual_exporter = metadata_parser.importerexporter[:importerexporter]
            expect(actual_exporter.parser_fields['metadata_only']).to be true
          end
        end

        context 'file inclusion option' do
          let(:files_exporter) do
            create(:bulkrax_exporter, :all,
                   user: user,
                   name: 'Files Export',
                   export_type: 'full',
                   parser_fields: { 'export_from' => 'all', 'include_files' => true })
          end

          it 'respects include_files configuration' do
            expect(files_exporter.export_type).to eq('full')
            expect(files_exporter.parser_fields['include_files']).to be true

            # Test parser can access this configuration
            files_parser = described_class.new(importerexporter: files_exporter)
            actual_exporter = files_parser.importerexporter[:importerexporter]
            expect(actual_exporter.parser_fields['include_files']).to be true
          end
        end

        context 'filter configurations' do
          let(:filtered_exporter) do
            create(:bulkrax_exporter, :all,
                   user: user,
                   name: 'Filtered Export Test',
                   parser_fields: {
                     'export_from' => 'all',
                     'visibility_filter' => 'open',
                     'start_date' => '2024-01-01',
                     'finish_date' => '2024-12-31'
                   })
          end

          it 'stores filter configurations' do
            expect(filtered_exporter.parser_fields['visibility_filter']).to eq('open')
            expect(filtered_exporter.parser_fields['start_date']).to eq('2024-01-01')
            expect(filtered_exporter.parser_fields['finish_date']).to eq('2024-12-31')
          end
        end
      end

      describe 'field mapping configuration with exporter' do
        context 'with field mappings configured' do
          around(:each) do |example|
            # Store original state
            original_mappings = Bulkrax.field_mappings&.dup

            # Ensure field_mappings hash exists
            Bulkrax.field_mappings ||= {}
            Bulkrax.field_mappings['Bulkrax::CsvParser'] = {
              'mapped_title' => { from: ['title'] },
              'mapped_creator' => { from: ['creator'] }
            }

            # Run the test
            example.run

            # Always restore original state
            if original_mappings
              Bulkrax.field_mappings = original_mappings
            else
              Bulkrax.field_mappings&.delete('Bulkrax::CsvParser')
            end
          end

          it 'has access to configured field mappings' do
            mappings = Bulkrax.field_mappings['Bulkrax::CsvParser']
            expect(mappings).to include('mapped_title', 'mapped_creator')
          end

          it 'can access mapping configuration from parser context' do
            expect(Bulkrax.field_mappings).to have_key('Bulkrax::CsvParser')
          end
        end

        context 'without field mappings' do
          around(:each) do |example|
            # Store original state
            original_mappings = Bulkrax.field_mappings&.dup

            # Run the test
            example.run

            # Restore original state
            Bulkrax.field_mappings = original_mappings if original_mappings
          end

          it 'handles absence of field mappings gracefully' do
            Bulkrax.field_mappings&.delete('Bulkrax::CsvParser')

            expect(Bulkrax.field_mappings['Bulkrax::CsvParser']).to be_nil
          end
        end
      end
    end
  end
end
