# frozen_string_literal: true

require 'rails_helper'
require 'csv'

RSpec.describe Bulkrax::SampleCsvService::CsvBuilder do
  let(:service) { instance_double(Bulkrax::SampleCsvService) }
  let(:csv_builder) { described_class.new(service) }
  let(:column_builder) { instance_double(Bulkrax::SampleCsvService::ColumnBuilder) }
  let(:row_builder) { instance_double(Bulkrax::SampleCsvService::RowBuilder) }

  before do
    # Allow the builder instances to be created
    allow(Bulkrax::SampleCsvService::ColumnBuilder).to receive(:new).with(service).and_return(column_builder)
    allow(Bulkrax::SampleCsvService::RowBuilder).to receive(:new).with(service).and_return(row_builder)
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

      expect(Bulkrax::SampleCsvService::ColumnBuilder).to have_received(:new).with(service)
      expect(Bulkrax::SampleCsvService::RowBuilder).to have_received(:new).with(service)
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

    it 'calls write_rows with the CSV object' do
      allow(CSV).to receive(:open).with(file_path, "w").and_yield(csv_double)

      csv_builder.write_to_file(file_path)

      expect(csv_builder).to have_received(:write_rows).with(csv_double)
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

    it 'calls write_rows with the CSV object' do
      allow(CSV).to receive(:generate).and_yield(csv_double).and_return("csv,string")

      csv_builder.generate_string

      expect(csv_builder).to have_received(:write_rows).with(csv_double)
    end
  end

  describe 'private methods' do
    describe '#write_rows' do
      let(:csv_double) { instance_double(CSV) }
      let(:rows) do
        [
          ['header1', 'header2'],
          ['desc1', 'desc2'],
          ['data1', 'data2']
        ]
      end

      before do
        allow(csv_builder).to receive(:csv_rows).and_return(rows)
      end

      it 'writes each row to the CSV' do
        allow(csv_double).to receive(:<<)

        csv_builder.send(:write_rows, csv_double)

        expect(csv_double).to have_received(:<<).with(['header1', 'header2'])
        expect(csv_double).to have_received(:<<).with(['desc1', 'desc2'])
        expect(csv_double).to have_received(:<<).with(['data1', 'data2'])
        expect(csv_double).to have_received(:<<).exactly(3).times
      end
    end

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

      it 'sets the header_row instance variable' do
        csv_builder.send(:csv_rows)

        expect(csv_builder.instance_variable_get(:@header_row)).to eq(header_row)
      end

      it 'calls remove_empty_columns on the result' do
        csv_builder.send(:csv_rows)

        expect(csv_builder).to have_received(:remove_empty_columns).once
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

      it 'sets required_headings to filtered required columns' do
        csv_builder.send(:fill_header_row)

        required_headings = csv_builder.instance_variable_get(:@required_headings)
        expect(required_headings).to eq(['work_type', 'title'])
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

          # col1 is required, col3 has data, col2 and col4 should be removed
          expect(result[0]).to eq(['col1', 'col3'])
          expect(result[1]).to eq(['desc1', 'desc3'])
          expect(result[2]).to eq(['data1', 'data3'])
          expect(result[3]).to eq(['data2', 'data4'])
        end

        it 'keeps required columns even if empty' do
          rows = [
            ['col1', 'col2'],
            ['desc1', 'desc2'],
            [nil, 'data2'],
            ['', 'data3']
          ]
          csv_builder.instance_variable_set(:@required_headings, ['col1'])

          result = csv_builder.send(:remove_empty_columns, rows)

          expect(result[0]).to include('col1')
        end
      end
    end

    describe '#keep_column?' do
      before do
        csv_builder.instance_variable_set(:@required_headings, ['work_type', 'title'])
      end

      context 'with required column' do
        it 'returns true for required heading' do
          column = ['work_type', 'desc', nil, nil]

          result = csv_builder.send(:keep_column?, column)

          expect(result).to be true
        end
      end

      context 'with non-required column' do
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

        it 'returns false if column has only empty strings' do
          column = ['creator', 'desc', '', '']

          result = csv_builder.send(:keep_column?, column)

          expect(result).to be false
        end

        it 'returns false if column has only "---" placeholders' do
          column = ['creator', 'desc', '---', '---']

          result = csv_builder.send(:keep_column?, column)

          expect(result).to be false
        end

        it 'returns true if at least one data value exists' do
          column = ['creator', 'desc', '---', 'John', nil, '']

          result = csv_builder.send(:keep_column?, column)

          expect(result).to be true
        end
      end
    end
  end

  describe 'integration' do
    it 'generates a complete CSV string with proper structure' do
      # Set up the full mock chain
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
