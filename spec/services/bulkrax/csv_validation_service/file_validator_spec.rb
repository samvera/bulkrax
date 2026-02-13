# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvValidationService::FileValidator do
  let(:csv_data) do
    [
      { file: 'image1.jpg', source_identifier: 'work1' },
      { file: 'document.pdf', source_identifier: 'work2' },
      { file: nil, source_identifier: 'work3' }
    ]
  end

  let(:zip_file) do
    zip = Tempfile.new(['test', '.zip'])
    Zip::File.open(zip.path, create: true) do |zipfile|
      zipfile.get_output_stream('image1.jpg') { |f| f.write('fake image data') }
      zipfile.get_output_stream('document.pdf') { |f| f.write('fake pdf data') }
    end
    zip.rewind
    zip
  end

  after do
    zip_file&.close
    zip_file&.unlink
  end

  describe '#count_references' do
    it 'counts total file references in CSV' do
      validator = described_class.new(csv_data, zip_file)
      expect(validator.count_references).to eq(2)
    end

    it 'returns 0 when no files referenced' do
      empty_data = [{ file: nil }, { file: '' }]
      validator = described_class.new(empty_data, zip_file)
      expect(validator.count_references).to eq(0)
    end
  end

  describe '#missing_files' do
    it 'returns empty array when all files are found' do
      validator = described_class.new(csv_data, zip_file)
      expect(validator.missing_files).to be_empty
    end

    it 'identifies missing files' do
      data_with_missing = csv_data + [{ file: 'missing.jpg' }]
      validator = described_class.new(data_with_missing, zip_file)
      expect(validator.missing_files).to include('missing.jpg')
    end

    it 'returns empty array when no zip provided' do
      validator = described_class.new(csv_data, nil)
      expect(validator.missing_files).to be_empty
    end

    context 'with paths in file references' do
      let(:csv_data_with_paths) do
        [
          { file: 'images/photo.jpg', source_identifier: 'work1' },
          { file: 'documents/report.pdf', source_identifier: 'work2' }
        ]
      end

      let(:zip_with_paths) do
        zip = Tempfile.new(['test', '.zip'])
        Zip::File.open(zip.path, create: true) do |zipfile|
          zipfile.get_output_stream('subfolder/photo.jpg') { |f| f.write('fake image') }
          zipfile.get_output_stream('other/report.pdf') { |f| f.write('fake pdf') }
        end
        zip.rewind
        zip
      end

      after do
        zip_with_paths&.close
        zip_with_paths&.unlink
      end

      it 'strips paths from CSV file references and matches by basename' do
        validator = described_class.new(csv_data_with_paths, zip_with_paths)
        expect(validator.missing_files).to be_empty
      end

      it 'identifies missing files when basenames do not match' do
        data_with_missing = csv_data_with_paths + [{ file: 'path/to/missing.jpg' }]
        validator = described_class.new(data_with_missing, zip_with_paths)
        expect(validator.missing_files).to eq(['missing.jpg'])
      end
    end
  end

  describe '#found_files_count' do
    it 'counts files found in zip' do
      validator = described_class.new(csv_data, zip_file)
      expect(validator.found_files_count).to eq(2)
    end

    it 'returns 0 when no zip provided' do
      validator = described_class.new(csv_data, nil)
      expect(validator.found_files_count).to eq(0)
    end

    it 'only counts files that exist in zip' do
      data_with_missing = csv_data + [{ file: 'missing.jpg' }]
      validator = described_class.new(data_with_missing, zip_file)
      expect(validator.found_files_count).to eq(2)
    end

    context 'with paths in file references and zip entries' do
      let(:csv_data_with_paths) do
        [
          { file: 'images/photo.jpg', source_identifier: 'work1' },
          { file: 'documents/report.pdf', source_identifier: 'work2' },
          { file: 'nested/path/to/file.txt', source_identifier: 'work3' }
        ]
      end

      let(:zip_with_nested_paths) do
        zip = Tempfile.new(['test', '.zip'])
        Zip::File.open(zip.path, create: true) do |zipfile|
          zipfile.get_output_stream('different/path/photo.jpg') { |f| f.write('image') }
          zipfile.get_output_stream('report.pdf') { |f| f.write('pdf') }
          zipfile.get_output_stream('deeply/nested/file.txt') { |f| f.write('text') }
        end
        zip.rewind
        zip
      end

      after do
        zip_with_nested_paths&.close
        zip_with_nested_paths&.unlink
      end

      it 'matches files by basename regardless of paths' do
        validator = described_class.new(csv_data_with_paths, zip_with_nested_paths)
        expect(validator.found_files_count).to eq(3)
      end

      it 'counts only matching basenames even with different paths' do
        mixed_data = [
          { file: 'path1/found.jpg', source_identifier: 'work1' },
          { file: 'path2/notfound.jpg', source_identifier: 'work2' }
        ]
        mixed_zip = Tempfile.new(['test', '.zip'])
        Zip::File.open(mixed_zip.path, create: true) do |zipfile|
          zipfile.get_output_stream('otherpath/found.jpg') { |f| f.write('image') }
        end
        mixed_zip.rewind

        validator = described_class.new(mixed_data, mixed_zip)
        expect(validator.found_files_count).to eq(1)

        mixed_zip.close
        mixed_zip.unlink
      end
    end
  end

  describe '#zip_included?' do
    it 'returns true when zip provided' do
      validator = described_class.new(csv_data, zip_file)
      expect(validator.zip_included?).to be true
    end

    it 'returns false when no zip provided' do
      validator = described_class.new(csv_data, nil)
      expect(validator.zip_included?).to be false
    end
  end
end
