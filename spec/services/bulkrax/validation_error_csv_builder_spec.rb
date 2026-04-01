# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::ValidationErrorCsvBuilder do
  let(:headers) { ['model', 'source_identifier', 'title', 'description'] }

  let(:csv_data) do
    [
      { source_identifier: 'id-001', raw_row: { 'model' => 'GenericWork', 'source_identifier' => 'id-001', 'title' => 'My Title', 'description' => 'A desc' } },
      { source_identifier: 'id-002', raw_row: { 'model' => 'GenericWork', 'source_identifier' => 'id-002', 'title' => 'Good Row', 'description' => '' } },
      { source_identifier: 'id-003', raw_row: { 'model' => 'Collection', 'source_identifier' => 'id-003', 'title' => '', 'description' => '' } }
    ]
  end

  describe '.build' do
    context 'when one row has a single error' do
      let(:row_errors) do
        [{ row: 2, severity: 'error', category: 'missing_required_value', column: 'title', value: nil, message: "Required field 'title' is missing" }]
      end

      it 'includes only the errored row plus the header' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        expect(rows.length).to eq(2)
      end

      it 'puts the original row number in column 1' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        expect(rows[1][0]).to eq('2')
      end

      it 'puts the error message in column 2' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        expect(rows[1][1]).to eq("Required field 'title' is missing")
      end

      it 'preserves the original row values in subsequent columns' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        expect(rows[1][2]).to eq('GenericWork')
        expect(rows[1][3]).to eq('id-001')
        expect(rows[1][4]).to eq('My Title')
      end

      it 'excludes clean rows' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        source_ids = rows[1..].map { |r| r[3] }
        expect(source_ids).not_to include('id-002')
      end
    end

    context 'when one row has multiple errors' do
      let(:row_errors) do
        [
          { row: 4, severity: 'error', category: 'missing_required_value', column: 'title', value: nil, message: 'Title is required' },
          { row: 4, severity: 'error', category: 'missing_required_value', column: 'description', value: nil, message: 'Description is required' }
        ]
      end

      it 'joins multiple error messages with " | "' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        expect(rows[1][1]).to eq('Title is required | Description is required')
      end
    end

    context 'when errors span multiple rows' do
      let(:row_errors) do
        [
          { row: 2, severity: 'error', category: 'duplicate_source_identifier', column: 'source_identifier', value: 'id-001', message: 'Duplicate source_identifier' },
          { row: 4, severity: 'warning', category: 'missing_required_value', column: 'title', value: nil, message: 'Title is required' }
        ]
      end

      it 'includes one output row per errored input row' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        expect(rows.length).to eq(3) # header + 2 errored rows
      end

      it 'outputs errored rows in original order' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        expect(rows[1][3]).to eq('id-001')
        expect(rows[2][3]).to eq('id-003')
      end
    end

    context 'header row' do
      let(:row_errors) { [{ row: 2, severity: 'error', category: 'test', column: 'title', value: nil, message: 'Error' }] }

      it 'has "row" as the first column and "errors" as the second' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        expect(rows.first[0]).to eq('row')
        expect(rows.first[1]).to eq('errors')
      end

      it 'preserves the original headers after the row and errors columns' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        expect(rows.first[2..]).to eq(headers)
      end
    end
  end
end
