# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvTemplate::FileValidator do
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

    context 'with delimiter-separated file references in a single cell' do
      let(:csv_data_multi) do
        [{ file: 'Cornus_drummondii.jpg|ArtThumbnail.JPG', source_identifier: 'work1' }]
      end

      let(:zip_with_both) do
        zip = Tempfile.new(['test', '.zip'])
        Zip::File.open(zip.path, create: true) do |zipfile|
          zipfile.get_output_stream('Cornus_drummondii.jpg') { |f| f.write('img') }
          zipfile.get_output_stream('ArtThumbnail.JPG') { |f| f.write('thumb') }
        end
        zip.rewind
        zip
      end

      after do
        zip_with_both.close
        zip_with_both.unlink
      end

      it 'splits on the delimiter and reports no missing files when both are present' do
        validator = described_class.new(csv_data_multi, zip_with_both)
        expect(validator.missing_files).to be_empty
      end

      it 'counts each individual file reference' do
        validator = described_class.new(csv_data_multi, zip_with_both)
        expect(validator.found_files_count).to eq(2)
      end

      it 'reports only the truly missing file when one is absent from the zip' do
        zip = Tempfile.new(['test', '.zip'])
        Zip::File.open(zip.path, create: true) do |zipfile|
          zipfile.get_output_stream('Cornus_drummondii.jpg') { |f| f.write('img') }
        end
        zip.rewind
        validator = described_class.new(csv_data_multi, zip)
        expect(validator.missing_files).to eq(['ArtThumbnail.JPG'])
        zip.close
        zip.unlink
      end
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

  describe '#possible_missing_files?' do
    it 'returns false when no file references in CSV' do
      empty_data = [{ file: nil }, { file: '' }]
      validator = described_class.new(empty_data, zip_file)

      expect(validator.possible_missing_files?).to be false
    end

    it 'returns true when files referenced but no zip provided' do
      validator = described_class.new(csv_data, nil)

      expect(validator.possible_missing_files?).to be true
    end

    it 'returns false when zip provided even if some files missing from zip' do
      data_with_missing = csv_data + [{ file: 'missing.jpg' }]
      validator = described_class.new(data_with_missing, zip_file)

      expect(validator.possible_missing_files?).to be false
    end

    it 'returns false when all referenced files are found in zip' do
      validator = described_class.new(csv_data, zip_file)

      expect(validator.possible_missing_files?).to be false
    end

    context 'with no files referenced' do
      let(:no_files_data) do
        [
          { source_identifier: 'work1' },
          { source_identifier: 'work2' }
        ]
      end

      it 'returns false even when zip is provided' do
        validator = described_class.new(no_files_data, zip_file)

        expect(validator.possible_missing_files?).to be false
      end

      it 'returns false when no zip provided' do
        validator = described_class.new(no_files_data, nil)

        expect(validator.possible_missing_files?).to be false
      end
    end

    context 'with paths in file references' do
      let(:csv_data_with_paths) do
        [
          { file: 'images/photo.jpg', source_identifier: 'work1' },
          { file: 'documents/report.pdf', source_identifier: 'work2' }
        ]
      end

      let(:zip_with_matching_files) do
        zip = Tempfile.new(['test', '.zip'])
        Zip::File.open(zip.path, create: true) do |zipfile|
          zipfile.get_output_stream('photo.jpg') { |f| f.write('fake image') }
          zipfile.get_output_stream('report.pdf') { |f| f.write('fake pdf') }
        end
        zip.rewind
        zip
      end

      after do
        zip_with_matching_files&.close
        zip_with_matching_files&.unlink
      end

      it 'returns false when all files found (basename matching)' do
        validator = described_class.new(csv_data_with_paths, zip_with_matching_files)

        expect(validator.possible_missing_files?).to be false
      end

      it 'returns true when files referenced but no zip' do
        validator = described_class.new(csv_data_with_paths, nil)

        expect(validator.possible_missing_files?).to be true
      end
    end

    context 'edge cases' do
      it 'returns false for empty CSV data array' do
        validator = described_class.new([], zip_file)

        expect(validator.possible_missing_files?).to be false
      end

      it 'handles mix of present and absent file references' do
        mixed_data = [
          { file: 'image1.jpg', source_identifier: 'work1' },
          { file: nil, source_identifier: 'work2' },
          { file: '', source_identifier: 'work3' }
        ]
        validator = described_class.new(mixed_data, zip_file)

        expect(validator.possible_missing_files?).to be false
      end
    end
  end

  # Characterisation coverage for how the `file` cell is split when counting
  # references. These specs pin the current behaviour (always uses
  # Bulkrax.multi_value_element_split_on, ignoring any configured `file`
  # split) so the change is visible when the implementation is refactored.
  describe 'split behaviour for the file column' do
    let(:csv_data) { [{ file: 'sun.jpg;moon.jpg', source_identifier: 'work1' }] }

    context 'with no `file` mapping configured' do
      it 'splits on Bulkrax.multi_value_element_split_on' do
        validator = described_class.new(csv_data, nil)
        expect(validator.count_references).to eq(1)
        expect(validator.possible_missing_files?).to be true
      end
    end

    context 'when the `file` mapping configures a non-default split' do
      around do |spec|
        old = Bulkrax.field_mappings['Bulkrax::CsvParser']
        Bulkrax.field_mappings['Bulkrax::CsvParser'] = { 'file' => { split: ',' } }
        spec.run
        Bulkrax.field_mappings['Bulkrax::CsvParser'] = old
      end

      it 'currently ignores the configured split and uses the default (pre-refactor behaviour)' do
        # Default /\s*[:;|]\s*/ splits the ";" from csv_data. A correctly-
        # configured split would be `,` and would NOT split "sun.jpg;moon.jpg".
        zip = Tempfile.new(['test', '.zip'])
        Zip::File.open(zip.path, create: true) do |zipfile|
          zipfile.get_output_stream('sun.jpg') { |f| f.write('a') }
          zipfile.get_output_stream('moon.jpg') { |f| f.write('b') }
        end
        zip.rewind
        validator = described_class.new(csv_data, zip)
        # Default split pattern splits on ';' → 2 files found, 0 missing.
        # When the refactor lands, the `,` configuration will keep
        # "sun.jpg;moon.jpg" as a single token and neither filename will
        # match the zip entries.
        expect(validator.found_files_count).to eq(2)
        expect(validator.missing_files).to eq([])
        zip.close
        zip.unlink
      end
    end
  end
end
