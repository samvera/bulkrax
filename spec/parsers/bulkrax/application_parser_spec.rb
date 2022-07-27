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
      # TODO(alishaevn): determine if it's a way to get around the "uninitialized constant Bulkrax::Site" error.
      # or is that against best practices to test for a model that exists in a different app?
      let(:site) { instance_double(Site, id: 1, account_id: 1) }
      let(:account) { instance_double(Account, id: 1, name: 'bulkrax') }

      before do
        ENV['SETTINGS__MULTITENANCY__ENABLED'] = 'true'
        # Site.instance.account.name = 'bulkrax'

        # allow(Site.instance.account).to receive(name).and_return('bulkrax')

        # allow_any_instance_of(Site).to receive(instance).and_return({})

        allow(Site).to receive(:instance).and_return(site)

        # allow(Site).to receive(:instance).and_return({})
        allow(Site.instance).to receive(:account).and_return(account)
        # allow(Site.instance.account).to receive(:name).and_return('bulkrax')

        # allow(Site).to receive(:instance).and_return({account: {name: 'bulkrax'}})
      end

      context 'in a hyku enabled app' do
        it 'sets the import path correctly' do
          # site = instance_double(Site, account: account)
          # byebug
          expect(importer.parser.base_path).to eq('tmp/imports/bulkrax')
        end

        xit 'sets the export path correctly' do
          expect(importer.parser.base_path).to eq('tmp/exports/bulkrax')
        end
      end

      context 'in a hyrax app' do
        xit 'sets the import path correctly' do
          expect(importer.parser.base_path).to eq('tmp/imports')
        end

        xit 'sets the export path correctly' do
          expect(importer.parser.base_path).to eq('tmp/exports')
        end
      end
    end
  end
end
