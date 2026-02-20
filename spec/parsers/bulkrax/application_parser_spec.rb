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
  end
end
