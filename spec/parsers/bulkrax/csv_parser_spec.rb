# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe CsvParser do
    describe '#create_works' do
      subject { described_class.new(importer) }
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
          expect(subject.source_identifer).to eq(:source_identifier)
        end

        it 'has a work id field' do
          expect(subject.work_identifer).to eq(:source)
        end

        it 'has custom source and work id fields' do
          subject.importerexporter.field_mapping['title']['source_identifier'] = true
          expect(subject.source_identifier).to eq('title')
          expect(subject.work_identifier).to eq('title')
        end

        it 'counts the correct number of works and collections' do
          expect(subject.total).to eq(2)
          expect(subject.collections_total).to eq(2)
        end
      end
    end

    describe '#write_partial_import_file', clean_downloads: true do
      subject        { described_class.new(importer) }
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv_failed) }
      let(:file)     { fixture_file_upload('./spec/fixtures/csv/ok.csv') }

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

    describe '#create_parent_child_relationships' do
      subject { described_class.new(importer) }
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
      subject                { described_class.new(importer) }
      let(:importer)         { FactoryBot.create(:bulkrax_importer_csv_failed, entries: [entry_failed, entry_succeeded, entry_collection]) }
      let(:entry_failed)     { FactoryBot.create(:bulkrax_csv_entry_failed, raw_metadata: { title: 'Failed' }) }
      let(:entry_succeeded)  { FactoryBot.create(:bulkrax_csv_entry, raw_metadata: { title: 'Succeeded' }) }
      let(:entry_collection) { FactoryBot.create(:bulkrax_csv_entry_collection, raw_metadata: { title: 'Collection' }, last_error: 'failed') }
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
  end
end
