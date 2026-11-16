# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe BagitParser do
    describe '#retrieve_cloud_files' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_bagit_csv) }
      let(:parser) { described_class.new(importer) }

      after { FileUtils.rm_rf(parser.path_for_import) }

      context 'with a safe, uniquely named file' do
        let(:files) { { '0' => { 'url' => 'https://example.com/bag.zip', 'file_name' => 'bag.zip' } } }

        before { allow(Bulkrax::CloudSourceValidator).to receive(:validate!).and_return(true) }

        it 'validates the source, runs the job synchronously with a relative filename, and returns the resolved absolute path' do
          expect(Bulkrax::DownloadCloudFileJob).to receive(:perform_now)
            .with(files['0'], importer_id: importer.id, relative_filename: 'bag.zip')

          result = parser.retrieve_cloud_files(files, importer)

          expect(Bulkrax::CloudSourceValidator).to have_received(:validate!).with(files['0'])
          expect(result).to eq(File.expand_path(File.join(parser.path_for_import, 'bag.zip')))
        end
      end

      context 'with a file name that attempts to escape the importer workspace' do
        let(:files) { { '0' => { 'url' => 'https://example.com/bag.zip', 'file_name' => '../../../etc/passwd' } } }

        before { allow(Bulkrax::CloudSourceValidator).to receive(:validate!).and_return(true) }

        it 'raises before running any job' do
          expect(Bulkrax::DownloadCloudFileJob).not_to receive(:perform_now)

          expect { parser.retrieve_cloud_files(files, importer) }
            .to raise_error(Bulkrax::UnsafePathError)
        end
      end

      context 'with an unsafe source' do
        let(:files) { { '0' => { 'url' => 'http://169.254.169.254/latest/meta-data/', 'file_name' => 'bag.zip' } } }

        it 'raises before running any job' do
          expect(Bulkrax::DownloadCloudFileJob).not_to receive(:perform_now)

          expect { parser.retrieve_cloud_files(files, importer) }
            .to raise_error(Bulkrax::UnsafeCloudSourceError)
        end
      end

      context 'with an absolute file name' do
        let(:files) { { '0' => { 'url' => 'https://example.com/bag.zip', 'file_name' => '/bag.zip' } } }

        before { allow(Bulkrax::CloudSourceValidator).to receive(:validate!).and_return(true) }

        it 'raises before running any job' do
          expect(Bulkrax::DownloadCloudFileJob).not_to receive(:perform_now)

          expect { parser.retrieve_cloud_files(files, importer) }
            .to raise_error(Bulkrax::UnsafePathError)
        end
      end

      context 'with a file name containing a `..` segment that would still resolve inside the workspace' do
        let(:files) { { '0' => { 'url' => 'https://example.com/bag.zip', 'file_name' => 'sub/../bag.zip' } } }

        before { allow(Bulkrax::CloudSourceValidator).to receive(:validate!).and_return(true) }

        it 'raises before running any job' do
          expect(Bulkrax::DownloadCloudFileJob).not_to receive(:perform_now)

          expect { parser.retrieve_cloud_files(files, importer) }
            .to raise_error(Bulkrax::UnsafePathError)
        end
      end

      context 'with no files' do
        it 'returns nil' do
          expect(parser.retrieve_cloud_files({ '0' => nil }, importer)).to be_nil
        end
      end
    end
  end
end
