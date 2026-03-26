# frozen_string_literal: true

require 'rails_helper'
require 'csv'

RSpec.describe Bulkrax::CsvTemplate::CsvBuilder do
  let(:service) { instance_double('TemplateContext') }
  let(:csv_builder) { described_class.new(service) }
  let(:column_builder) { instance_double(Bulkrax::CsvTemplate::ColumnBuilder) }
  let(:row_builder) { instance_double(Bulkrax::CsvTemplate::RowBuilder) }

  before do
    allow(Bulkrax::CsvTemplate::ColumnBuilder).to receive(:new).with(service).and_return(column_builder)
    allow(Bulkrax::CsvTemplate::RowBuilder).to receive(:new).with(service).and_return(row_builder)
  end

  describe 'IGNORED_PROPERTIES' do
    it 'contains expected system properties to exclude' do
      expect(described_class::IGNORED_PROPERTIES).to include(
        'admin_set_id', 'created_at', 'updated_at', 'internal_resource'
      )
    end
  end

  describe '#initialize' do
    it 'creates column and row builders with the service' do
      described_class.new(service)

      expect(Bulkrax::CsvTemplate::ColumnBuilder).to have_received(:new).with(service)
      expect(Bulkrax::CsvTemplate::RowBuilder).to have_received(:new).with(service)
    end

    it 'initializes header_row and required_headings as empty' do
      expect(csv_builder.instance_variable_get(:@header_row)).to be_nil
      expect(csv_builder.instance_variable_get(:@required_headings)).to eq([])
    end
  end

  describe '#write_to_file' do
    let(:file_path) { '/tmp/test.csv' }
    let(:csv_double) { instance_double(CSV) }

    before do
      allow(csv_builder).to receive(:write_rows)
    end

    it 'opens a CSV file for writing' do
      allow(CSV).to receive(:open).with(file_path, "w").and_yield(csv_double)

      csv_builder.write_to_file(file_path)

      expect(CSV).to have_received(:open).with(file_path, "w")
    end
  end

  describe '#generate_string' do
    let(:csv_double) { instance_double(CSV) }

    before do
      allow(csv_builder).to receive(:write_rows)
    end

    it 'generates a CSV string' do
      allow(CSV).to receive(:generate).and_yield(csv_double).and_return("csv,string")

      result = csv_builder.generate_string

      expect(result).to eq("csv,string")
    end
  end

  describe 'private methods' do
    describe '#csv_rows' do
      let(:header_row) { ['work_type', 'title', 'creator'] }
      let(:explanation_row) { ['Work type desc', 'Title desc', 'Creator desc'] }
      let(:model_rows) { [['GenericWork', 'Required', 'Optional']] }

      before do
        allow(csv_builder).to receive(:fill_header_row).and_return(header_row)
        allow(row_builder).to receive(:build_explanation_row).with(header_row).and_return(explanation_row)
        allow(row_builder).to receive(:build_model_rows).with(header_row).and_return(model_rows)
        allow(csv_builder).to receive(:remove_empty_columns) { |rows| rows }
      end

      it 'builds rows in correct order' do
        result = csv_builder.send(:csv_rows)

        expect(result[0]).to eq(header_row)
        expect(result[1]).to eq(explanation_row)
        expect(result[2]).to eq(model_rows[0])
      end
    end

    describe '#fill_header_row' do
      let(:all_columns) { ['work_type', 'title', 'creator', 'admin_set_id', 'created_at'] }
      let(:required_columns) { ['work_type', 'title'] }

      before do
        allow(column_builder).to receive(:all_columns).and_return(all_columns)
        allow(column_builder).to receive(:required_columns).and_return(required_columns)
      end

      it 'filters out ignored properties' do
        result = csv_builder.send(:fill_header_row)

        expect(result).to include('work_type', 'title', 'creator')
        expect(result).not_to include('admin_set_id', 'created_at')
      end
    end

    describe '#remove_empty_columns' do
      context 'with empty input' do
        it 'returns empty array for empty input' do
          result = csv_builder.send(:remove_empty_columns, [])

          expect(result).to eq([])
        end
      end

      context 'with data rows' do
        let(:rows_with_empty) do
          [
            ['col1', 'col2', 'col3', 'col4'],
            ['desc1', 'desc2', 'desc3', 'desc4'],
            ['data1', nil, 'data3', '---'],
            ['data2', '', 'data4', '---']
          ]
        end

        before do
          csv_builder.instance_variable_set(:@required_headings, ['col1'])
        end

        it 'removes columns with no real data' do
          result = csv_builder.send(:remove_empty_columns, rows_with_empty)

          expect(result[0]).to eq(['col1', 'col3'])
        end
      end
    end

    describe '#keep_column?' do
      before do
        csv_builder.instance_variable_set(:@required_headings, ['work_type', 'title'])
      end

      it 'returns true for required heading' do
        column = ['work_type', 'desc', nil, nil]

        result = csv_builder.send(:keep_column?, column)

        expect(result).to be true
      end

      it 'returns true if column has real data' do
        column = ['creator', 'desc', 'John', 'Jane']

        result = csv_builder.send(:keep_column?, column)

        expect(result).to be true
      end

      it 'returns false if column has only nil values' do
        column = ['creator', 'desc', nil, nil]

        result = csv_builder.send(:keep_column?, column)

        expect(result).to be false
      end
    end
  end

  describe 'integration' do
    it 'generates a complete CSV string with proper structure' do
      allow(column_builder).to receive(:all_columns).and_return(['work_type', 'title', 'admin_set_id'])
      allow(column_builder).to receive(:required_columns).and_return(['work_type'])
      allow(row_builder).to receive(:build_explanation_row).and_return(['Type desc', 'Title desc'])
      allow(row_builder).to receive(:build_model_rows).and_return([['GenericWork', 'Required']])

      result = csv_builder.generate_string

      csv = CSV.parse(result)
      expect(csv[0]).to eq(['work_type', 'title']) # admin_set_id filtered out
      expect(csv[1]).to eq(['Type desc', 'Title desc'])
      expect(csv[2]).to eq(['GenericWork', 'Required'])
    end
  end
end
