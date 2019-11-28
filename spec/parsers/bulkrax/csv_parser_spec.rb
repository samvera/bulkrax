require 'rails_helper'

module Bulkrax
  RSpec.describe CsvParser do
    describe '#create_works' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }
      let(:entry) { FactoryBot.create(:bulkrax_entry, importerexporter: importer) }
      subject { described_class.new(importer) }

      before(:each) do
        allow(Bulkrax::CsvEntry).to receive_message_chain(:where, :first_or_create!).and_return(entry)
        allow(entry).to receive(:id)
        allow(Bulkrax::ImportWorkJob).to receive(:perform_later)
      end

      context 'with malformed CSV' do
        before(:each) do
          importer.parser_fields = { csv_path: './spec/fixtures/csv/malformed.csv' }
        end

        it 'returns an empty array, and records the error on the importer' do
          subject.create_works
          expect(importer.errors.details[:base].first[:error]).to eq('CSV::MalformedCSVError'.to_sym)
        end
      end

      context 'without an identifier column' do
        before(:each) do
          importer.parser_fields = { csv_path: './spec/fixtures/csv/bad.csv' }
        end

        it 'skips all of the lines' do
          expect(subject.importerexporter).not_to receive(:increment_counters)
          subject.create_works
        end
      end

      context 'with a nil value in the identifier column' do
        before(:each) do
          importer.parser_fields = { csv_path: './spec/fixtures/csv/ok.csv' }
        end

        it 'skips the bad line' do
          expect(subject).to receive(:increment_counters).once
          subject.create_works
        end
      end

      context 'with good data' do
        before(:each) do
          importer.parser_fields = { csv_path: './spec/fixtures/csv/good.csv' }
        end

        it 'processes the line' do
          expect(subject).to receive(:increment_counters).twice
          subject.create_works
        end
      end
    end
  end
end
