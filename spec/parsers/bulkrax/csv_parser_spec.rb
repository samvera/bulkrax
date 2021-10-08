# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe CsvParser do
    subject { described_class.new(importer) }
    let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }

    describe '#collections' do
      before do
        importer.parser_fields = { import_file_path: './spec/fixtures/csv/mixed_works_and_collections.csv' }
      end

      it 'includes collection titles listed in the :collection column' do
        expect(subject.collections).to include({ title: "Second Work's Collection" })
      end

      it 'includes rows whose :model is set to Collection' do
        expect(subject.collections.collect { |w| w[:title] })
          .to contain_exactly('Collection 1 Title', 'Collection 2 Title', "Second Work's Collection")
      end

      it 'matches :model column case-insensitively' do
        allow(subject).to receive_message_chain(:records, :map).and_return([{ model: 'cOlEcTiOn' }])

        expect(subject.collections).to include({ model: 'cOlEcTiOn' })
      end

      context 'when Bulkrax.collection_field_mapping' do
        before do
          allow(subject)
            .to receive(:records)
            .and_return(
              [
                { collection: 'collection mapping', title: 'W1', model: 'work' },
                { parent: 'parent mapping', title: 'W2', model: 'work' }
              ]
            )
        end

        context 'is set' do
          before do
            allow(subject).to receive(:collection_field_mapping).and_return(:parent)
          end

          it 'the collection field mapping is used' do
            expect(subject.collections).to include({ title: 'parent mapping' })
            expect(subject.collections).not_to include({ title: 'collection mapping' })
          end
        end

        context 'is not set' do
          it 'the mapping falls back on :collection' do
            expect(subject.collections).not_to include({ title: 'parent mapping' })
            expect(subject.collections).to include({ title: 'collection mapping' })
          end
        end
      end

      describe ':model field mappings' do
        before do
          allow(subject)
            .to receive(:records)
            .and_return(
              [
                { map_1: 'Collection', title: 'C1' },
                { map_2: 'Collection', title: 'C2' },
                { model: 'Collection', title: 'C3' }
              ]
            )
        end

        context 'when :model has field mappings' do
          before do
            allow(subject).to receive(:model_field_mappings).and_return(['map_1', 'map_2', 'model'])
          end

          it 'uses the field mappings' do
            expect(subject.collections).to include({ map_1: 'Collection', title: 'C1' })
            expect(subject.collections).to include({ map_2: 'Collection', title: 'C2' })
          end
        end

        context 'when :model does not have field mappings' do
          it 'uses :model' do
            expect(subject.collections).to include({ model: 'Collection', title: 'C3' })
            expect(subject.collections).not_to include({ map_1: 'Collection', title: 'C1' })
            expect(subject.collections).not_to include({ map_2: 'Collection', title: 'C2' })
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

    describe '#create_collections' do
      context 'when importing collections by title through works' do
        before do
          importer.parser_fields = { import_file_path: './spec/fixtures/csv/good.csv' }
          allow(ImportCollectionJob).to receive(:perform_now)
        end

        it 'creates CSV collection entries for each collection' do
          expect { subject.create_collections }.to change(CsvCollectionEntry, :count).by(2)
        end

        it 'runs an ImportCollectionJob for each entry' do
          expect(ImportCollectionJob).to receive(:perform_now).twice

          subject.create_collections
        end
      end

      context 'when importing collections with metadata' do
        before do
          importer.parser_fields = { import_file_path: './spec/fixtures/csv/collections.csv' }
          allow(ImportCollectionJob).to receive(:perform_now)
        end

        it 'creates CSV collection entries for each collection' do
          expect { subject.create_collections }.to change(CsvCollectionEntry, :count).by(2)
        end

        it 'runs an ImportCollectionJob for each entry' do
          expect(ImportCollectionJob).to receive(:perform_now).twice

          subject.create_collections
        end
      end

      describe 'setting collection entry identifiers' do
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
          let(:record_hash) { { title: 'no source id | alt title' } }

          it "uses the record's first title as the entry's identifier" do
            subject.create_collections

            expect(importer.entries.last.identifier).to eq('no source id')
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
          expect(subject.total).to eq(2)
          expect(subject.collections_total).to eq(2)
        end
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
        # TODO(alishaevn): get this spec to work
        before do
          ENV['HYKU_MULTITENANT'] = 'true'
          # allow(Site).to receive(instance).and_return({})
          # allow(Site.instance).to receive(account).and_return({})
          # allow(Site.instance.account).to receive(name).and_return('hyku')

          # allow('base_path').to receive(::Site.instance.account.name).and_return('hyku')
        end

        xit 'returns the path of the partial import file' do
          expect(subject.write_partial_import_file(file))
            .to eq("tmp/imports/hyku/#{importer.id}_#{importer.created_at.strftime('%Y%m%d%H%M%S')}/failed_corrected_entries.csv")
        end
      end
    end

    describe '#create_parent_child_relationships' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv_complex) }
      let(:entry_1) { FactoryBot.build(:bulkrax_entry, importerexporter: importer, identifier: '123456789') }
      let(:entry_2) { FactoryBot.build(:bulkrax_entry, importerexporter: importer, identifier: '234567891') }
      let(:entry_3) { FactoryBot.build(:bulkrax_entry, importerexporter: importer, identifier: '345678912') }
      let(:entry_4) { FactoryBot.build(:bulkrax_entry, importerexporter: importer, identifier: '456789123') }

      before do
        allow(Bulkrax::CsvEntry).to receive(:where).with(identifier: '123456789', importerexporter_id: importer.id, importerexporter_type: 'Bulkrax::Importer').and_return([entry_1])
        allow(Bulkrax::CsvEntry).to receive(:where).with(identifier: '234567891', importerexporter_id: importer.id, importerexporter_type: 'Bulkrax::Importer').and_return([entry_2])
        allow(Bulkrax::CsvEntry).to receive(:where).with(identifier: '345678912', importerexporter_id: importer.id, importerexporter_type: 'Bulkrax::Importer').and_return([entry_3])
        allow(Bulkrax::CsvEntry).to receive(:where).with(identifier: '456789123', importerexporter_id: importer.id, importerexporter_type: 'Bulkrax::Importer').and_return([entry_4])
      end

      it 'sets up the list of parents and children' do
        expect(subject.parents).to eq("123456789" => ["234567891"], "234567891" => ["345678912"], "345678912" => ["456789123"], "456789123" => ["234567891"])
      end

      it 'invokes Bulkrax::ChildRelationshipsJob' do
        expect(Bulkrax::ChildRelationshipsJob).to receive(:perform_later).exactly(4).times
        subject.create_parent_child_relationships
      end
    end

    describe '#create_new_entries' do
      subject(:parser) { described_class.new(exporter) }
      let(:exporter)   { FactoryBot.create(:bulkrax_exporter_worktype) }

      it 'invokes Bulkrax::ExportWorkJob once per Entry' do
        # Use OpenStructs to simulate the behavior of ActiveFedora::SolrHit instances.
        work_ids = [OpenStruct.new(id: SecureRandom.alphanumeric(9)), OpenStruct.new(id: SecureRandom.alphanumeric(9))]
        expect(ActiveFedora::SolrService).to receive(:query).and_return(work_ids)
        expect(Bulkrax::ExportWorkJob).to receive(:perform_now).exactly(2).times
        parser.create_new_entries
      end

      context 'with an export limit of 1' do
        let(:exporter) { FactoryBot.create(:bulkrax_exporter_worktype, limit: 1) }

        it 'invokes Bulkrax::ExportWorkJob once' do
          # Use OpenStructs to simulate the behavior of ActiveFedora::SolrHit instances.
          work_ids = [OpenStruct.new(id: SecureRandom.alphanumeric(9)), OpenStruct.new(id: SecureRandom.alphanumeric(9))]
          expect(ActiveFedora::SolrService).to receive(:query).and_return(work_ids)
          expect(Bulkrax::ExportWorkJob).to receive(:perform_now).exactly(1).times
          parser.create_new_entries
        end
      end

      context 'with an export limit of 0' do
        let(:exporter) { FactoryBot.create(:bulkrax_exporter_worktype, limit: 0) }

        it 'invokes Bulkrax::ExportWorkJob once per Entry' do
          # Use OpenStructs to simulate the behavior of ActiveFedora::SolrHit instances.
          work_ids = [OpenStruct.new(id: SecureRandom.alphanumeric(9)), OpenStruct.new(id: SecureRandom.alphanumeric(9))]
          expect(ActiveFedora::SolrService).to receive(:query).and_return(work_ids)
          expect(Bulkrax::ExportWorkJob).to receive(:perform_now).exactly(2).times
          parser.create_new_entries
        end
      end
    end

    describe '#path_to_files' do
      pending
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
        allow(ActiveFedora::SolrService).to receive(:query).and_return(OpenStruct.new(id: work_id))
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

    describe '#collection_field_mapping' do
      context 'when the mapping is set' do
        before do
          allow(Bulkrax).to receive(:collection_field_mapping).and_return({ 'Bulkrax::CsvEntry' => 'parent' })
        end

        it 'returns the mapping' do
          expect(subject.collection_field_mapping).to eq(:parent)
        end
      end

      context 'when the mapping is not set' do
        before do
          allow(Bulkrax).to receive(:collection_field_mapping).and_return({})
        end

        it 'returns :collection' do
          expect(subject.collection_field_mapping).to eq(:collection)
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
  end
end
