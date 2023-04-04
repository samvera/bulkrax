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

      it 'sends the create_* methods based on given types' do
        expect(application_parser).to receive(:create_works)
        expect(application_parser).to receive(:create_collections)
        expect(application_parser).to receive(:create_file_sets)
        expect(application_parser).to receive(:create_relationships)

        application_parser.create_objects(%w[collection work file_set relationship])
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
  end
end
