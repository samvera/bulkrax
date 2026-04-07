# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ApplicationParser do
    let(:importer) { FactoryBot.create(:bulkrax_importer) }
    let(:exporter_with_no_field_mapping) { FactoryBot.create(:bulkrax_exporter) }
    let(:exporter_with_field_mapping) do
      FactoryBot.create(:bulkrax_exporter, field_mapping: {
                          "bulkrax_identifier" => { "from" => ["source_identifier"], "source_identifier" => true }
                        })
    end
    let(:site) { instance_double(Site, id: 1, account_id: 1) }
    let(:account) { instance_double(Account, id: 1, name: 'bulkrax') }

    describe '#create_objects' do
      subject(:application_parser) { described_class.new(importer) }

      it 'create_works calls create_objects' do
        expect(application_parser).to receive(:create_objects).with(['work'])
        application_parser.create_works
      end

      it 'create_collections calls create_objects' do
        expect(application_parser).to receive(:create_objects).with(['collection'])
        application_parser.create_collections
      end

      it 'create_file_sets calls create_objects' do
        expect(application_parser).to receive(:create_objects).with(['file_set'])
        application_parser.create_file_sets
      end

      it 'create_relationships calls create_objects' do
        expect(application_parser).to receive(:create_objects).with(['relationship'])
        application_parser.create_relationships
      end
    end

    describe '#get_field_mapping_hash_for' do
      context 'with `[{}]` as the field mapping' do
        subject(:application_parser) { described_class.new(importer) }

        it 'returns an empty hash' do
          expect(application_parser.get_field_mapping_hash_for('source_identifier')).to eq({})
        end
      end

      context 'with `nil` as the field mapping' do
        subject(:application_parser) { described_class.new(exporter_with_no_field_mapping) }

        it 'returns an empty hash' do
          expect(application_parser.get_field_mapping_hash_for('source_identifier')).to eq({})
        end
      end

      context 'with valid field mapping' do
        subject(:application_parser) { described_class.new(exporter_with_field_mapping) }

        it 'returns the field mapping for the given key' do
          expect(application_parser.get_field_mapping_hash_for('source_identifier')).to eq({ "bulkrax_identifier" => { "from" => ["source_identifier"], "source_identifier" => true } })
        end
      end
    end

    describe '#base_path' do
      before do
        allow(Site).to receive(:instance).and_return(site)
        allow(Site.instance).to receive(:account).and_return(account)
      end

      context 'in a multi tenant app' do
        before do
          ENV['SETTINGS__MULTITENANCY__ENABLED'] = 'true'
        end

        it 'sets the import path correctly' do
          expect(importer.parser.base_path).to eq('tmp/imports/bulkrax')
        end

        it 'sets the export path correctly' do
          expect(importer.parser.base_path('export')).to eq('tmp/exports/bulkrax')
        end
      end

      context 'in a non multi tenant app' do
        # this includes hyrax apps AND single tenant hyku apps

        before do
          ENV['SETTINGS__MULTITENANCY__ENABLED'] = 'false'
        end

        it 'sets the import path correctly' do
          expect(importer.parser.base_path).to eq('tmp/imports')
        end

        it 'sets the export path correctly' do
          expect(importer.parser.base_path('export')).to eq('tmp/exports')
        end
      end
    end

    describe '#zip?' do
      let(:parser) { described_class.new(importer) }

      subject { parser.zip? }

      before { importer.parser_fields['import_file_path'] = path if path }

      context 'when the parser import_file_path is empty' do
        let(:path) { nil }
        it { is_expected.to be_falsey }
      end

      context 'when the parser import_file_path is for a csv' do
        let(:path) { 'spec/fixtures/csv/good.csv' }
        it { is_expected.to be_falsey }
      end

      context 'when the parser import_file_path is for a zip file' do
        let(:path) { 'spec/fixtures/zip/simple.zip' }
        it { is_expected.to be_truthy }
      end
    end

    describe '#remove_spaces_from_filenames' do
      let(:parser) { described_class.new(importer) }
      let(:before_filenames) { ['spec/fixtures/csv/files/no_space.jpg', 'spec/fixtures/csv/files/has space.jpg'] }
      let(:after_filenames) { ['spec/fixtures/csv/files/no_space.jpg', 'spec/fixtures/csv/files/has_space.jpg'] }

      before do
        before_filenames.each do |file_path|
          File.write(file_path, 'w')
        end

        allow(Dir).to receive(:glob).and_return(before_filenames)
      end

      after do
        after_filenames.each do |file_path|
          File.delete(file_path)
        end
      end

      it 'renames files to replace spaces with underscores' do
        expect(File.exist?('spec/fixtures/csv/files/has space.jpg')).to eq(true)
        expect(File.exist?('spec/fixtures/csv/files/has_space.jpg')).to eq(false)

        parser.remove_spaces_from_filenames

        expect(File.exist?('spec/fixtures/csv/files/has space.jpg')).to eq(false)
        expect(File.exist?('spec/fixtures/csv/files/has_space.jpg')).to eq(true)
      end

      it 'does not alter files that do not have spaces in their name' do
        expect(File.exist?('spec/fixtures/csv/files/no_space.jpg')).to eq(true)

        parser.remove_spaces_from_filenames

        expect(File.exist?('spec/fixtures/csv/files/no_space.jpg')).to eq(true)
      end
    end

    describe '#unzip' do
      let(:parser)    { described_class.new(importer) }
      let(:unzip_dir) { File.realpath(Dir.mktmpdir) }

      before do
        dir = unzip_dir
        importer.define_singleton_method(:importer_unzip_path) { |**| dir }
      end
      after { FileUtils.rm_rf(unzip_dir) }

      def build_zip(zip_path, entries)
        Zip::File.open(zip_path, create: true) do |zip|
          entries.each do |name, content|
            next if name.end_with?('/')
            zip.get_output_stream(name) { |f| f.write(content) }
          end
        end
      end

      def with_zip(entries)
        zip_file = Tempfile.new(['import', '.zip'])
        build_zip(zip_file.path, entries)
        yield zip_file.path
      ensure
        zip_file.close!
      end

      context 'when the zip contains a top-level wrapper directory (directory zipped, not contents)' do
        it 'extracts files directly into the unzip path, stripping the wrapper directory' do
          with_zip('directory/data.csv' => 'title,identifier',
                   'directory/files/a.jpg' => 'jpg-content') do |zip_path|
            parser.unzip(zip_path)

            expect(File.exist?(File.join(unzip_dir, 'data.csv'))).to be true
            expect(File.exist?(File.join(unzip_dir, 'files', 'a.jpg'))).to be true
            expect(File.exist?(File.join(unzip_dir, 'directory', 'data.csv'))).to be false
          end
        end
      end

      context 'when the zip contains files at the root (contents zipped, not directory)' do
        it 'extracts files directly into the unzip path without stripping any prefix' do
          with_zip('data.csv' => 'title,identifier',
                   'files/a.jpg' => 'jpg-content') do |zip_path|
            parser.unzip(zip_path)

            expect(File.exist?(File.join(unzip_dir, 'data.csv'))).to be true
            expect(File.exist?(File.join(unzip_dir, 'files', 'a.jpg'))).to be true
          end
        end
      end

      context 'when the zip is flat (image files at root, no files/ subdirectory)' do
        it 'moves extracted files into a files/ subdirectory' do
          with_zip('Cornus_drummondii.jpg' => 'jpg-content',
                   'ArtThumbnail.JPG' => 'jpg-content') do |zip_path|
            parser.unzip(zip_path)

            expect(File.exist?(File.join(unzip_dir, 'files', 'Cornus_drummondii.jpg'))).to be true
            expect(File.exist?(File.join(unzip_dir, 'files', 'ArtThumbnail.JPG'))).to be true
            expect(File.exist?(File.join(unzip_dir, 'Cornus_drummondii.jpg'))).to be false
            expect(File.exist?(File.join(unzip_dir, 'ArtThumbnail.JPG'))).to be false
          end
        end
      end

      context 'when the zip contains macOS junk entries (__MACOSX, .DS_Store, ._files)' do
        it 'skips junk entries and extracts only real files' do
          with_zip('directory/data.csv' => 'title,identifier',
                   'directory/.DS_Store' => 'junk',
                   'directory/files/a.jpg' => 'jpg-content',
                   '__MACOSX/directory/._.DS_Store' => 'junk',
                   '__MACOSX/directory/._data.csv' => 'junk',
                   '__MACOSX/directory/._files' => 'junk',
                   '__MACOSX/directory/files/._a.jpg' => 'junk') do |zip_path|
            parser.unzip(zip_path)

            expect(File.exist?(File.join(unzip_dir, 'data.csv'))).to be true
            expect(File.exist?(File.join(unzip_dir, 'files', 'a.jpg'))).to be true
            expect(Dir.exist?(File.join(unzip_dir, '__MACOSX'))).to be false
            expect(File.exist?(File.join(unzip_dir, '.DS_Store'))).to be false
          end
        end
      end
    end

    describe '#macos_junk_entry?' do
      let(:parser) { described_class.new(importer) }

      it 'returns true for __MACOSX entries' do
        expect(parser.macos_junk_entry?('__MACOSX/directory/._file.csv')).to be true
      end

      it 'returns true for .DS_Store entries' do
        expect(parser.macos_junk_entry?('directory/.DS_Store')).to be true
      end

      it 'returns true for ._ prefixed entries' do
        expect(parser.macos_junk_entry?('directory/._file.csv')).to be true
      end

      it 'returns false for normal files' do
        expect(parser.macos_junk_entry?('directory/data.csv')).to be false
        expect(parser.macos_junk_entry?('directory/files/image.jpg')).to be false
      end
    end
  end
end
