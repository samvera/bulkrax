# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe CsvParser do
    describe '#retrieve_cloud_files' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }
      let(:parser) { described_class.new(importer) }

      after { FileUtils.rm_rf(parser.path_for_import) }

      context 'with a safe, uniquely named file' do
        let(:files) { { '0' => { 'url' => 'https://example.com/a.pdf', 'file_name' => 'a.pdf' } } }

        before { allow(Bulkrax::CloudSourceValidator).to receive(:validate!).and_return(true) }

        it 'validates the source, enqueues the job with a relative filename, and records the resolved absolute path' do
          expect(Bulkrax::DownloadCloudFileJob).to receive(:perform_later)
            .with(files['0'], importer_id: importer.id, relative_filename: File.join('files', 'a.pdf'))

          parser.retrieve_cloud_files(files, importer)

          expect(Bulkrax::CloudSourceValidator).to have_received(:validate!).with(files['0'])
          expect(importer[:parser_fields]['original_file_paths'])
            .to eq([File.expand_path(File.join(parser.path_for_import, 'files', 'a.pdf'))])
        end
      end

      context 'with a file name that attempts to escape the importer workspace' do
        let(:files) { { '0' => { 'url' => 'https://example.com/a.pdf', 'file_name' => '../../../etc/passwd' } } }

        before { allow(Bulkrax::CloudSourceValidator).to receive(:validate!).and_return(true) }

        it 'raises before enqueueing any job' do
          expect(Bulkrax::DownloadCloudFileJob).not_to receive(:perform_later)

          expect { parser.retrieve_cloud_files(files, importer) }
            .to raise_error(Bulkrax::UnsafePathError)
        end
      end

      context 'with a batch where the first file is valid and the second is unsafe' do
        let(:files) do
          {
            '0' => { 'url' => 'https://example.com/a.pdf', 'file_name' => 'a.pdf' },
            '1' => { 'url' => 'https://example.com/b.pdf', 'file_name' => '../../../etc/passwd' }
          }
        end

        before { allow(Bulkrax::CloudSourceValidator).to receive(:validate!).and_return(true) }

        it 'enqueues a job for neither file — the whole batch is validated before anything is enqueued' do
          expect(Bulkrax::DownloadCloudFileJob).not_to receive(:perform_later)

          expect { parser.retrieve_cloud_files(files, importer) }
            .to raise_error(Bulkrax::UnsafePathError)
        end
      end

      context 'with an unsafe source' do
        let(:files) { { '0' => { 'url' => 'http://169.254.169.254/latest/meta-data/', 'file_name' => 'a.pdf' } } }

        it 'raises before enqueueing any job' do
          expect(Bulkrax::DownloadCloudFileJob).not_to receive(:perform_later)

          expect { parser.retrieve_cloud_files(files, importer) }
            .to raise_error(Bulkrax::UnsafeCloudSourceError)
        end
      end

      # The 'files/' prefix is joined onto the raw file_name before it's
      # resolved, which normalizes away both a leading `/` (File.join
      # doesn't treat it as absolute once it's not the first argument) and
      # a `..` segment (File.expand_path just cancels it out) — silently
      # turning a suspicious filename into one that *looks* like it landed
      # safely inside root. The raw file_name must be rejected outright,
      # before that join ever happens.
      context 'with a file name that is absolute, even though it would resolve inside the workspace after joining' do
        let(:files) { { '0' => { 'url' => 'https://example.com/a.pdf', 'file_name' => '/files/a.pdf' } } }

        before { allow(Bulkrax::CloudSourceValidator).to receive(:validate!).and_return(true) }

        it 'raises before enqueueing any job' do
          expect(Bulkrax::DownloadCloudFileJob).not_to receive(:perform_later)

          expect { parser.retrieve_cloud_files(files, importer) }
            .to raise_error(Bulkrax::UnsafePathError)
        end
      end

      context 'with a file name containing a `..` segment that would still resolve inside the workspace' do
        let(:files) { { '0' => { 'url' => 'https://example.com/a.pdf', 'file_name' => 'sub/../a.pdf' } } }

        before { allow(Bulkrax::CloudSourceValidator).to receive(:validate!).and_return(true) }

        it 'raises before enqueueing any job' do
          expect(Bulkrax::DownloadCloudFileJob).not_to receive(:perform_later)

          expect { parser.retrieve_cloud_files(files, importer) }
            .to raise_error(Bulkrax::UnsafePathError)
        end
      end

      context '#plan_cloud_files and #dispatch_cloud_files!' do
        let(:files) { { '0' => { 'url' => 'https://example.com/a.pdf', 'file_name' => 'a.pdf' } } }

        before { allow(Bulkrax::CloudSourceValidator).to receive(:validate!).and_return(true) }

        it 'plans the batch without enqueueing anything' do
          expect(Bulkrax::DownloadCloudFileJob).not_to receive(:perform_later)

          plan = parser.plan_cloud_files(files)

          expect(plan).to eq([[files['0'], File.join('files', 'a.pdf'), File.expand_path(File.join(parser.path_for_import, 'files', 'a.pdf'))]])
        end

        it 'dispatches a previously computed plan' do
          plan = parser.plan_cloud_files(files)

          expect(Bulkrax::DownloadCloudFileJob).to receive(:perform_later)
            .with(files['0'], importer_id: importer.id, relative_filename: File.join('files', 'a.pdf'))

          parser.dispatch_cloud_files!(plan, importer)
        end
      end

      context 'with an auth_header' do
        let(:files) { { '0' => { 'url' => 'https://example.com/a.pdf', 'file_name' => 'a.pdf', 'auth_header' => { 'Authorization' => 'Bearer xyz' } } } }

        before { allow(Bulkrax::CloudSourceValidator).to receive(:validate!).and_return(true) }

        it 'still merges auth_header into headers before validating and enqueueing' do
          allow(Bulkrax::DownloadCloudFileJob).to receive(:perform_later)

          parser.retrieve_cloud_files(files, importer)

          expect(files['0']['headers']).to eq('Authorization' => 'Bearer xyz')
        end
      end
    end
  end
end
