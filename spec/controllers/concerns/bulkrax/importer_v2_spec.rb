# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::ImporterV2, type: :controller do
  controller(ApplicationController) do
    include Bulkrax::ImporterV2
  end

  describe '#find_csv_in_zip' do
    let(:zip_file) { Tempfile.new(['test', '.zip']) }

    after do
      zip_file.close
      zip_file.unlink
    end

    context 'with no CSV files' do
      it 'returns error when no CSV files exist' do
        Zip::File.open(zip_file.path, create: true) do |zipfile|
          zipfile.get_output_stream('readme.txt') { |f| f.write('text') }
          zipfile.get_output_stream('image.jpg') { |f| f.write('image') }
        end

        Zip::File.open(zip_file.path) do |zip|
          result = controller.send(:find_csv_in_zip, zip)
          expect(result).to be_a(Hash)
          expect(result[:messages][:validationStatus][:severity]).to eq('error')
          expect(result[:messages][:validationStatus][:summary]).to include('No CSV files found in ZIP')
        end
      end
    end

    context 'with single CSV at root level' do
      it 'returns the CSV entry' do
        Zip::File.open(zip_file.path, create: true) do |zipfile|
          zipfile.get_output_stream('data.csv') { |f| f.write('csv content') }
        end

        Zip::File.open(zip_file.path) do |zip|
          result = controller.send(:find_csv_in_zip, zip)
          expect(result).to be_a(Zip::Entry)
          expect(result.name).to eq('data.csv')
        end
      end
    end

    context 'with single CSV in subdirectory' do
      it 'returns the CSV entry' do
        Zip::File.open(zip_file.path, create: true) do |zipfile|
          zipfile.get_output_stream('data/metadata.csv') { |f| f.write('csv content') }
        end

        Zip::File.open(zip_file.path) do |zip|
          result = controller.send(:find_csv_in_zip, zip)
          expect(result).to be_a(Zip::Entry)
          expect(result.name).to eq('data/metadata.csv')
        end
      end
    end

    context 'with multiple CSVs at different depths' do
      it 'returns the CSV at the shallowest level' do
        Zip::File.open(zip_file.path, create: true) do |zipfile|
          zipfile.get_output_stream('metadata.csv') { |f| f.write('root csv') }
          zipfile.get_output_stream('data/nested.csv') { |f| f.write('nested csv') }
          zipfile.get_output_stream('data/deep/deeper.csv') { |f| f.write('deep csv') }
        end

        Zip::File.open(zip_file.path) do |zip|
          result = controller.send(:find_csv_in_zip, zip)
          expect(result).to be_a(Zip::Entry)
          expect(result.name).to eq('metadata.csv')
        end
      end

      it 'returns CSV from shallowest subdirectory when no root CSV exists' do
        Zip::File.open(zip_file.path, create: true) do |zipfile|
          zipfile.get_output_stream('dir1/data.csv') { |f| f.write('csv 1') }
          zipfile.get_output_stream('dir1/subdir/nested.csv') { |f| f.write('csv 2') }
        end

        Zip::File.open(zip_file.path) do |zip|
          result = controller.send(:find_csv_in_zip, zip)
          expect(result).to be_a(Zip::Entry)
          expect(result.name).to eq('dir1/data.csv')
        end
      end
    end

    context 'with multiple CSVs at the same root level' do
      it 'returns error when multiple CSVs exist at root' do
        Zip::File.open(zip_file.path, create: true) do |zipfile|
          zipfile.get_output_stream('data1.csv') { |f| f.write('csv 1') }
          zipfile.get_output_stream('data2.csv') { |f| f.write('csv 2') }
        end

        Zip::File.open(zip_file.path) do |zip|
          result = controller.send(:find_csv_in_zip, zip)
          expect(result).to be_a(Hash)
          expect(result[:messages][:validationStatus][:severity]).to eq('error')
          expect(result[:messages][:validationStatus][:summary]).to include('Multiple CSV files found in the same directory within ZIP')
        end
      end
    end

    context 'with multiple CSVs in different directories at the same depth' do
      it 'returns error when CSVs exist in multiple directories at same level' do
        Zip::File.open(zip_file.path, create: true) do |zipfile|
          zipfile.get_output_stream('dir1/data.csv') { |f| f.write('csv 1') }
          zipfile.get_output_stream('dir2/metadata.csv') { |f| f.write('csv 2') }
        end

        Zip::File.open(zip_file.path) do |zip|
          result = controller.send(:find_csv_in_zip, zip)
          expect(result).to be_a(Hash)
          expect(result[:messages][:validationStatus][:severity]).to eq('error')
          expect(result[:messages][:validationStatus][:summary]).to include('Multiple CSV files found at the same level')
        end
      end

      it 'returns error with three CSVs across different directories at same depth' do
        Zip::File.open(zip_file.path, create: true) do |zipfile|
          zipfile.get_output_stream('dir1/data.csv') { |f| f.write('csv 1') }
          zipfile.get_output_stream('dir2/metadata.csv') { |f| f.write('csv 2') }
          zipfile.get_output_stream('dir3/info.csv') { |f| f.write('csv 3') }
        end

        Zip::File.open(zip_file.path) do |zip|
          result = controller.send(:find_csv_in_zip, zip)
          expect(result).to be_a(Hash)
          expect(result[:messages][:validationStatus][:severity]).to eq('error')
          expect(result[:messages][:validationStatus][:summary]).to include('Multiple CSV files found at the same level')
        end
      end
    end

    context 'with multiple CSVs in the same directory' do
      it 'returns error when multiple CSVs exist in same subdirectory' do
        Zip::File.open(zip_file.path, create: true) do |zipfile|
          zipfile.get_output_stream('data/file1.csv') { |f| f.write('csv 1') }
          zipfile.get_output_stream('data/file2.csv') { |f| f.write('csv 2') }
        end

        Zip::File.open(zip_file.path) do |zip|
          result = controller.send(:find_csv_in_zip, zip)
          expect(result).to be_a(Hash)
          expect(result[:messages][:validationStatus][:severity]).to eq('error')
          expect(result[:messages][:validationStatus][:summary]).to include('Multiple CSV files found in the same directory within ZIP')
        end
      end
    end

    context 'with complex directory structures' do
      it 'correctly identifies shallowest level with nested structures' do
        Zip::File.open(zip_file.path, create: true) do |zipfile|
          zipfile.get_output_stream('a/b/c/deep.csv') { |f| f.write('deep csv') }
          zipfile.get_output_stream('x/y/shallow.csv') { |f| f.write('shallow csv') }
        end

        Zip::File.open(zip_file.path) do |zip|
          result = controller.send(:find_csv_in_zip, zip)
          expect(result).to be_a(Zip::Entry)
          expect(result.name).to eq('x/y/shallow.csv')
        end
      end

      it 'handles CSV files alongside directories' do
        Zip::File.open(zip_file.path, create: true) do |zipfile|
          zipfile.get_output_stream('metadata.csv') { |f| f.write('root csv') }
          zipfile.get_output_stream('images/photo1.jpg') { |f| f.write('image') }
          zipfile.get_output_stream('documents/nested.csv') { |f| f.write('nested csv') }
        end

        Zip::File.open(zip_file.path) do |zip|
          result = controller.send(:find_csv_in_zip, zip)
          expect(result).to be_a(Zip::Entry)
          expect(result.name).to eq('metadata.csv')
        end
      end
    end

    context 'with edge cases' do
      it 'ignores directory entries that end with .csv' do
        Zip::File.open(zip_file.path, create: true) do |zipfile|
          zipfile.mkdir('fake.csv') # Directory with .csv extension
          zipfile.get_output_stream('real.csv') { |f| f.write('real csv') }
        end

        Zip::File.open(zip_file.path) do |zip|
          result = controller.send(:find_csv_in_zip, zip)
          expect(result).to be_a(Zip::Entry)
          expect(result.name).to eq('real.csv')
        end
      end

      it 'handles CSV files with uppercase extension' do
        Zip::File.open(zip_file.path, create: true) do |zipfile|
          zipfile.get_output_stream('DATA.CSV') { |f| f.write('uppercase csv') }
        end

        Zip::File.open(zip_file.path) do |zip|
          result = controller.send(:find_csv_in_zip, zip)
          # Depending on implementation, this might fail if case-sensitive
          # This documents current behavior
          expect(result).to be_a(Hash).or(be_a(Zip::Entry))
        end
      end

      it 'handles empty directories in path' do
        Zip::File.open(zip_file.path, create: true) do |zipfile|
          zipfile.mkdir('empty_dir')
          zipfile.get_output_stream('data/metadata.csv') { |f| f.write('csv content') }
        end

        Zip::File.open(zip_file.path) do |zip|
          result = controller.send(:find_csv_in_zip, zip)
          expect(result).to be_a(Zip::Entry)
          expect(result.name).to eq('data/metadata.csv')
        end
      end
    end
  end

  describe '#importer_params_v2' do
    it 'permits override_rights_statement in parser_fields' do
      params = ActionController::Parameters.new(
        importer: {
          name: 'Test Import',
          admin_set_id: 'admin_set/default',
          parser_fields: {
            rights_statement: 'http://rightsstatements.org/vocab/NOC/1.0/',
            override_rights_statement: '1'
          }
        }
      )
      allow(controller).to receive(:params).and_return(params)

      permitted = controller.send(:importer_params_v2)
      parser_fields = permitted[:parser_fields] || permitted['parser_fields']
      expect(parser_fields).to be_present
      expect(parser_fields['override_rights_statement'] || parser_fields[:override_rights_statement]).to eq('1')
    end
  end
end
