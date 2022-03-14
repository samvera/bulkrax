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

    describe '#parent_field_mapping' do
      subject(:xml_parser) { described_class.new(importer) }
      let(:importer) { FactoryBot.create(:bulkrax_importer_xml) }

      context 'when the mapping is set' do
        before do
          importer.field_mapping = {
              'parents_test' => { 'from' => ['parents_column'], related_parents_field_mapping: true },
              'children_test' => { 'from' => ['children_column'], related_children_field_mapping: true },
              'unrelated' => { 'from' => ['unrelated_column'] }
          }
        end
        it 'returns the mapping' do
          expect(xml_parser.related_parents_parsed_mapping).to eq('parents_test')
        end
      end

      context 'when the mapping is not set' do
        it 'returns "parents" by default' do
          expect(xml_parser.related_parents_parsed_mapping).to eq('parents')
        end
      end
    end

    describe '#model_field_mappings' do
      subject(:xml_parser) { described_class.new(importer) }
      let(:importer) { FactoryBot.create(:bulkrax_importer_xml) }

      context 'when mappings are set' do
        before do
          allow(Bulkrax)
            .to receive(:field_mappings)
            .and_return({ 'Bulkrax::XmlParser' => { 'model' => { from: ['map_1', 'map_2'] } } })
        end

        it 'includes the mappings' do
          expect(xml_parser.model_field_mappings).to include('map_1', 'map_2')
        end

        it 'always includes "model"' do
          expect(xml_parser.model_field_mappings).to include('model')
        end
      end

      context 'when mappings are set' do
        it 'falls back on "model"' do
          expect(xml_parser.model_field_mappings).to eq(['model'])
        end
      end
    end
  end
end
