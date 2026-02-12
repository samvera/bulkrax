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
