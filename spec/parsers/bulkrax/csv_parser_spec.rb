require 'rails_helper'

module Bulkrax
  RSpec.describe CsvParser do
    describe '#create_works' do
      let(:importer) { FactoryBot.build(:bulkrax_importer_csv) }
      subject { described_class.new(importer) }

      context 'with malformed CSV' do
        before(:each) do
          importer.parser_fields = { csv_path: './spec/fixtures/csv/malformed.csv' }
        end

        it 'returns and empty array, and records the error on the importer' do
          subject.records
          expect(importer.errors.details[:base].first[:error]).to eq('CSV::MalformedCSVError'.to_sym)
          expect(subject.records).to eq([])
        end
      end

      context 'without an identifier column' do
        before(:each) do
          importer.parser_fields = { csv_path: './spec/fixtures/csv/bad.csv' }
        end

        it 'returns and empty array, and records the error on the importer' do
          subject.records
          expect(importer.errors[:base].first).to eq('Identifier column is required')
          expect(subject.records).to eq([])
        end
      end

      context 'with a nil value in the identifier column' do
        before(:each) do
          importer.parser_fields = { csv_path: './spec/fixtures/csv/ok.csv' }
        end

        it 'skips the bad line' do
          expect(subject.records).to eq([{ identifier: '2', title: 'Another Title' }])
        end
      end

      context 'with good data' do
        before(:each) do
          importer.parser_fields = { csv_path: './spec/fixtures/csv/good.csv' }
        end

        it 'processes the line' do
          expect(subject.records).to eq([{ identifier: '1', title: 'Lovely Title' }])
        end
      end
    end
  end
end
