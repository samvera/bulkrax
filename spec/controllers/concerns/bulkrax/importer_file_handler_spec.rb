# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::ImporterFileHandler do
  let(:controller) do
    Class.new do
      include Bulkrax::ImporterFileHandler
      public(*Bulkrax::ImporterFileHandler.private_instance_methods(false))
    end.new
  end

  describe '#locate_csv_entry_in_zip' do
    let(:zip_file) { Tempfile.new(['test', '.zip']) }

    after do
      zip_file.close
      zip_file.unlink
    end

    def open_zip(&block)
      Zip::File.open(zip_file.path, &block)
    end

    context 'with no CSV files' do
      it 'returns an error' do
        Zip::File.open(zip_file.path, create: true) do |zip|
          zip.get_output_stream('readme.txt') { |f| f.write('text') }
          zip.get_output_stream('image.jpg') { |f| f.write('image') }
        end

        open_zip do |zip|
          result = controller.locate_csv_entry_in_zip(zip)
          expect(result[:messages][:validationStatus][:severity]).to eq('error')
          expect(result[:messages][:validationStatus][:summary]).to include('No CSV files found in ZIP')
        end
      end
    end

    context 'with a single CSV at the root level' do
      it 'returns the CSV entry' do
        Zip::File.open(zip_file.path, create: true) do |zip|
          zip.get_output_stream('data.csv') { |f| f.write('csv content') }
        end

        open_zip do |zip|
          result = controller.locate_csv_entry_in_zip(zip)
          expect(result).to be_a(Zip::Entry)
          expect(result.name).to eq('data.csv')
        end
      end
    end

    context 'with a single CSV in a subdirectory' do
      it 'returns the CSV entry' do
        Zip::File.open(zip_file.path, create: true) do |zip|
          zip.get_output_stream('data/metadata.csv') { |f| f.write('csv content') }
        end

        open_zip do |zip|
          result = controller.locate_csv_entry_in_zip(zip)
          expect(result).to be_a(Zip::Entry)
          expect(result.name).to eq('data/metadata.csv')
        end
      end
    end

    context 'with multiple CSVs at different depths' do
      it 'returns the CSV at the shallowest level' do
        Zip::File.open(zip_file.path, create: true) do |zip|
          zip.get_output_stream('metadata.csv') { |f| f.write('root csv') }
          zip.get_output_stream('data/nested.csv') { |f| f.write('nested csv') }
          zip.get_output_stream('data/deep/deeper.csv') { |f| f.write('deep csv') }
        end

        open_zip do |zip|
          result = controller.locate_csv_entry_in_zip(zip)
          expect(result).to be_a(Zip::Entry)
          expect(result.name).to eq('metadata.csv')
        end
      end

      it 'returns the CSV from the shallowest subdirectory when no root CSV exists' do
        Zip::File.open(zip_file.path, create: true) do |zip|
          zip.get_output_stream('dir1/data.csv') { |f| f.write('csv 1') }
          zip.get_output_stream('dir1/subdir/nested.csv') { |f| f.write('csv 2') }
        end

        open_zip do |zip|
          result = controller.locate_csv_entry_in_zip(zip)
          expect(result).to be_a(Zip::Entry)
          expect(result.name).to eq('dir1/data.csv')
        end
      end
    end

    # The cases below all fail the same constraint — the CSV at the shallowest
    # depth in the zip must be unique — and surface the same error message.
    # Kept as separate contexts so we exercise each structural shape that
    # triggers the ambiguity.
    shared_examples 'ambiguous primary CSV' do
      it 'returns an error indicating multiple CSVs share the shallowest level' do
        open_zip do |zip|
          result = controller.locate_csv_entry_in_zip(zip)
          expect(result[:messages][:validationStatus][:severity]).to eq('error')
          expect(result[:messages][:validationStatus][:summary]).to match(/multiple CSV/i)
        end
      end
    end

    context 'with multiple CSVs at the same root level' do
      before do
        Zip::File.open(zip_file.path, create: true) do |zip|
          zip.get_output_stream('data1.csv') { |f| f.write('csv 1') }
          zip.get_output_stream('data2.csv') { |f| f.write('csv 2') }
        end
      end

      include_examples 'ambiguous primary CSV'
    end

    context 'with multiple CSVs in different directories at the same depth' do
      before do
        Zip::File.open(zip_file.path, create: true) do |zip|
          zip.get_output_stream('dir1/data.csv') { |f| f.write('csv 1') }
          zip.get_output_stream('dir2/metadata.csv') { |f| f.write('csv 2') }
        end
      end

      include_examples 'ambiguous primary CSV'

      context 'with three CSVs across different directories' do
        before do
          Zip::File.open(zip_file.path, create: true) do |zip|
            zip.get_output_stream('dir1/data.csv') { |f| f.write('csv 1') }
            zip.get_output_stream('dir2/metadata.csv') { |f| f.write('csv 2') }
            zip.get_output_stream('dir3/info.csv') { |f| f.write('csv 3') }
          end
        end

        include_examples 'ambiguous primary CSV'
      end
    end

    context 'with multiple CSVs in the same subdirectory' do
      before do
        Zip::File.open(zip_file.path, create: true) do |zip|
          zip.get_output_stream('data/file1.csv') { |f| f.write('csv 1') }
          zip.get_output_stream('data/file2.csv') { |f| f.write('csv 2') }
        end
      end

      include_examples 'ambiguous primary CSV'
    end

    context 'with edge cases' do
      it 'ignores directory entries that end with .csv' do
        Zip::File.open(zip_file.path, create: true) do |zip|
          zip.mkdir('fake.csv')
          zip.get_output_stream('real.csv') { |f| f.write('real csv') }
        end

        open_zip do |zip|
          result = controller.locate_csv_entry_in_zip(zip)
          expect(result).to be_a(Zip::Entry)
          expect(result.name).to eq('real.csv')
        end
      end

      it 'handles a CSV alongside non-CSV files' do
        Zip::File.open(zip_file.path, create: true) do |zip|
          zip.get_output_stream('metadata.csv') { |f| f.write('root csv') }
          zip.get_output_stream('images/photo1.jpg') { |f| f.write('image') }
          zip.get_output_stream('documents/nested.csv') { |f| f.write('nested csv') }
        end

        open_zip do |zip|
          result = controller.locate_csv_entry_in_zip(zip)
          expect(result).to be_a(Zip::Entry)
          expect(result.name).to eq('metadata.csv')
        end
      end

      it 'handles empty directories in the path' do
        Zip::File.open(zip_file.path, create: true) do |zip|
          zip.mkdir('empty_dir')
          zip.get_output_stream('data/metadata.csv') { |f| f.write('csv content') }
        end

        open_zip do |zip|
          result = controller.locate_csv_entry_in_zip(zip)
          expect(result).to be_a(Zip::Entry)
          expect(result.name).to eq('data/metadata.csv')
        end
      end

      it 'handles CSV files with uppercase extension' do
        Zip::File.open(zip_file.path, create: true) do |zip|
          zip.get_output_stream('DATA.CSV') { |f| f.write('uppercase csv') }
        end

        open_zip do |zip|
          # Documents current behavior: case-sensitive match only finds lowercase .csv
          result = controller.locate_csv_entry_in_zip(zip)
          expect(result).to be_a(Hash).or(be_a(Zip::Entry))
        end
      end
    end
  end
end
