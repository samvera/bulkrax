# frozen_string_literal: true

require 'rails_helper'
require 'libxml'

module Bulkrax
  RSpec.describe ImporterJob, type: :job do
    subject(:importer_job) { described_class.new(importer: importer) }
    let(:importer) { FactoryBot.create(:bulkrax_importer_oai) }
    let(:parser) { importer.parser }
    let(:doc) { LibXML::XML::Document.file('./spec/fixtures/oai/oai-pmh-ListSets.xml') }
    let(:response) { OAI::ListSetsResponse.new(doc) }
    let(:collections_count) { doc.to_s.scan(/<set>(.*?)<\/set>/m).count }

    before do
      allow(Bulkrax::Importer).to receive(:find).with(1).and_return(importer)
    end

    describe 'successful job' do
      it 'calls import_works with false' do
        expect(importer).to receive(:import_objects)
        importer_job.perform(importer.id)
      end

      it 'calls import_works with true if only_updates_since_last_import=true' do
        expect(importer).to receive(:import_objects)
        importer_job.perform(importer.id, true)
      end

      before do
        allow(parser).to receive(:collections).and_return(response)
        allow(parser.collections).to receive(:count).and_return(collections_count)
      end

      it 'updates the current run counters' do
        expect(importer).to receive(:import_objects)
        importer_job.perform(importer.id)

        expect(importer.current_run.total_work_entries).to eq(10)
        expect(importer.current_run.total_collection_entries).to eq(5)
      end
    end

    describe 'failed job' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv_bad) }

      it 'returns for an invalid import' do
        expect(importer).not_to receive(:import_objects)
      end

      context 'with malformed CSV' do
        let(:importer) { FactoryBot.create(:bulkrax_importer_csv_bad, parser_fields: { 'import_file_path' => 'spec/fixtures/csv/malformed.csv' }) }

        it 'logs the error on the importer' do
          importer_job.perform(importer.id)
          expect(importer.status).to eq('Failed')
        end

        it 'does not reschedule the job' do
          expect(importer_job).not_to receive(:schedule)

          importer_job.perform(importer.id)
        end
      end

      context 'when the zip cannot be interpreted (e.g. no CSV inside)' do
        let(:zip_tmp) { Tempfile.new(['import', '.zip']) }
        let(:importer) do
          FactoryBot.create(:bulkrax_importer_csv, parser_fields: { 'import_file_path' => zip_tmp.path })
        end

        before do
          Zip::File.open(zip_tmp.path, create: true) do |z|
            z.get_output_stream('foo.jpg') { |f| f.write('jpg-bytes') }
          end
          zip_tmp.close
        end

        after { zip_tmp.unlink }

        it 'rescues the UnzipError and sets the importer status to Failed' do
          importer_job.perform(importer.id)
          expect(importer.reload.status).to eq('Failed')
        end

        it 'records the error message on the importer status' do
          importer_job.perform(importer.id)
          expect(importer.reload.current_status.error_message).to match(/no csv/i)
          expect(importer.current_status.error_class).to eq('Bulkrax::UnzipError')
        end
      end
    end

    # Dispatch tests for `#unzip_imported_file`. The full extraction
    # contracts are pinned in spec/parsers/bulkrax/csv_parser/unzip_spec.rb
    # and spec/parsers/bulkrax/application_parser_spec.rb; these specs
    # verify that the job calls the right method on the right parser for
    # each upload shape and parser type.
    describe '#unzip_imported_file dispatch' do
      let(:job) { described_class.new }

      # Memoized per example so the helpers below return the same path
      # consistently, and so the `after` hook cleans up exactly one dir
      # per example rather than leaving a trail of stray tmpdirs.
      let(:unzip_tmpdir) { Dir.mktmpdir }
      after { FileUtils.rm_rf(unzip_tmpdir) }

      # Shared setup for CsvParser-backed doubles. Not pulled out to a
      # `before` block at the `describe` level because one of the contexts
      # below uses an XmlParser double, and `instance_double` would reject
      # stubs for methods XmlParser doesn't implement (e.g.
      # `#remove_spaces_from_filenames`).
      def stub_csv_parser_defaults(parser)
        allow(parser).to receive(:file?).and_return(true)
        allow(parser).to receive(:importer_unzip_path).and_return(unzip_tmpdir)
        allow(parser).to receive(:remove_spaces_from_filenames)
      end

      def stub_xml_parser_defaults(parser)
        allow(parser).to receive(:file?).and_return(true)
        allow(parser).to receive(:importer_unzip_path).and_return(unzip_tmpdir)
      end

      context 'when the parser is a CsvParser with a zip upload' do
        let(:parser) { instance_double('Bulkrax::CsvParser') }

        it 'calls #unzip_with_primary_csv' do
          stub_csv_parser_defaults(parser)
          allow(parser).to receive(:zip?).and_return(true)
          allow(parser).to receive(:parser_fields).and_return('import_file_path' => '/tmp/bundle.zip')

          expect(parser).to receive(:unzip_with_primary_csv).with('/tmp/bundle.zip')

          job.send(:unzip_imported_file, parser)
        end
      end

      context 'when the parser is a CsvParser with a CSV + separate attachments zip' do
        let(:parser) { instance_double('Bulkrax::CsvParser') }

        it 'copies the CSV then calls #unzip_attachments_only' do
          stub_csv_parser_defaults(parser)
          allow(parser).to receive(:zip?).and_return(false)
          allow(parser).to receive(:zip_file?).with('/tmp/attach.zip').and_return(true)
          allow(parser).to receive(:parser_fields).and_return(
            'import_file_path' => '/tmp/metadata.csv',
            'attachments_zip_path' => '/tmp/attach.zip'
          )

          expect(parser).to receive(:copy_file).with('/tmp/metadata.csv').ordered
          expect(parser).to receive(:unzip_attachments_only).with('/tmp/attach.zip').ordered

          job.send(:unzip_imported_file, parser)
        end
      end

      context 'when the parser is CSV-only (no zip at all)' do
        let(:parser) { instance_double('Bulkrax::CsvParser') }

        it 'just copies the CSV' do
          stub_csv_parser_defaults(parser)
          allow(parser).to receive(:zip?).and_return(false)
          allow(parser).to receive(:zip_file?).with(nil).and_return(false)
          allow(parser).to receive(:parser_fields).and_return('import_file_path' => '/tmp/metadata.csv')

          expect(parser).to receive(:copy_file).with('/tmp/metadata.csv')

          job.send(:unzip_imported_file, parser)
        end
      end

      context 'when the parser does not implement CSV-specific unzip methods (e.g. XmlParser)' do
        # XmlParser inherits `#unzip` from ApplicationParser for verbatim
        # extraction. It must not receive `#unzip_with_primary_csv`, which
        # only exists on CsvParser. XmlParser also doesn't implement
        # `#remove_spaces_from_filenames`, so the `respond_to?` guard in
        # the job skips that post-step.
        let(:parser) { instance_double('Bulkrax::XmlParser') }

        it 'falls back to verbatim #unzip for a zip upload' do
          stub_xml_parser_defaults(parser)
          allow(parser).to receive(:zip?).and_return(true)
          allow(parser).to receive(:parser_fields).and_return('import_file_path' => '/tmp/bundle.zip')

          expect(parser).to receive(:unzip).with('/tmp/bundle.zip')

          job.send(:unzip_imported_file, parser)
        end

        it 'never takes the attachments-zip branch for an XML parser' do
          stub_xml_parser_defaults(parser)
          allow(parser).to receive(:zip?).and_return(false)
          # An XmlParser would never have `attachments_zip_path` set in
          # practice, but guard anyway — the branch should be skipped
          # because the parser doesn't respond to `#unzip_attachments_only`.
          allow(parser).to receive(:parser_fields).and_return(
            'import_file_path' => '/tmp/metadata.xml',
            'attachments_zip_path' => '/tmp/attach.zip'
          )

          expect(parser).to receive(:copy_file).with('/tmp/metadata.xml')

          job.send(:unzip_imported_file, parser)
        end
      end

      context 'when the parser is a BagitParser with a zip upload' do
        # BagitParser < CsvParser, so it inherits `#unzip_with_primary_csv`.
        # But BagIt archives do not contain a primary CSV — the method is
        # overridden on BagitParser to delegate to verbatim `#unzip`. The
        # job dispatches to the overridden method, which ends up calling
        # `#unzip` under the hood. We verify by stubbing `#unzip` on the
        # double and expecting the override to forward to it.
        let(:parser) { instance_double('Bulkrax::BagitParser') }

        it 'receives unzip_with_primary_csv which ultimately extracts verbatim via #unzip' do
          stub_csv_parser_defaults(parser)
          allow(parser).to receive(:zip?).and_return(true)
          allow(parser).to receive(:parser_fields).and_return('import_file_path' => '/tmp/bag.zip')

          expect(parser).to receive(:unzip_with_primary_csv).with('/tmp/bag.zip')

          job.send(:unzip_imported_file, parser)
        end
      end
    end

    describe 'schedulable' do
      before do
        allow(importer).to receive(:schedulable?).and_return(true)
        allow(importer).to receive(:next_import_at).and_return(1)
        allow(parser).to receive(:collections).and_return(response)
        allow(parser.collections).to receive(:count).and_return(collections_count)
      end

      it 'schedules import_works when schedulable?' do
        expect(importer).to receive(:import_objects)
        expect(described_class).to receive(:set).with(wait_until: 1).and_return(described_class)
        importer_job.perform(importer.id)
      end
    end
  end
end
