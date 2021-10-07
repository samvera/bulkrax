# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe XmlParser do
    describe '#create_works' do
      subject(:xml_parser) { described_class.new(importer) }
      let(:importer) { FactoryBot.create(:bulkrax_importer_xml) }
      let(:entry) { FactoryBot.create(:bulkrax_entry, importerexporter: importer) }

      before do
        Bulkrax.field_mappings['Bulkrax::XmlParser'] = {
          'title' => { from: ['TitleLargerEntity'] },
          'abstract' => { from: ['Abstract'] },
          'source' => { from: ['DrisUnique'], source_identifier: true }
        }
        allow(Bulkrax::XmlEntry).to receive_message_chain(:where, :first_or_create!).and_return(entry)
        allow(entry).to receive(:id)
        allow(Bulkrax::ImportWorkJob).to receive(:perform_later)
      end

      context 'with good data' do
        before do
          importer.parser_fields = {
            'import_file_path' => './spec/fixtures/xml/good.xml',
            'record_element' => 'ROW'
          }
        end

        context 'and import_type set to multiple' do
          before do
            importer.parser_fields.merge!('import_type' => 'multiple')
          end

          it 'processes the line' do
            expect(xml_parser).to receive(:increment_counters).twice
            xml_parser.create_works
          end

          it 'counts the correct number of works and collections' do
            expect(xml_parser.total).to eq(2)
            expect(xml_parser.collections_total).to eq(0)
          end
        end

        context 'and import_type set to single' do
          before do
            importer.parser_fields.merge!('import_type' => 'single')
          end

          it 'processes the line' do
            expect(xml_parser).to receive(:increment_counters).once
            xml_parser.create_works
          end

          it 'counts the correct number of works and collections' do
            expect(xml_parser.total).to eq(1)
            expect(xml_parser.collections_total).to eq(0)
          end
        end
      end
    end

    describe '#collection_field_mapping' do
      subject(:xml_parser) { described_class.new(importer) }
      let(:importer) { FactoryBot.create(:bulkrax_importer_xml) }

      context 'when the mapping is set' do
        before do
          allow(Bulkrax).to receive(:collection_field_mapping).and_return({ 'Bulkrax::XmlEntry' => 'parent' })
        end

        it 'returns the mapping' do
          expect(xml_parser.collection_field_mapping).to eq(:parent)
        end
      end

      context 'when the mapping is not set' do
        before do
          allow(Bulkrax).to receive(:collection_field_mapping).and_return({})
        end

        it 'returns :collection' do
          expect(xml_parser.collection_field_mapping).to eq(:collection)
        end
      end
    end
  end
end
