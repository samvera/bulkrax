# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ApplicationParser do
    describe '#get_field_mapping_hash_for' do
      let(:importer) { FactoryBot.create(:bulkrax_importer) }
      let(:exporter_with_no_field_mapping) { FactoryBot.create(:bulkrax_exporter) }
      let(:exporter_with_field_mapping) do
        FactoryBot.create(:bulkrax_exporter, field_mapping: {
                            "bulkrax_identifier" => { "from" => ["source_identifier"], "source_identifier" => true }
                          })
      end

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
  end
end
