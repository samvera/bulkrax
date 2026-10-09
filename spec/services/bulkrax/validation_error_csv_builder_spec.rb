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

      it 'includes all data rows plus the header' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        expect(rows.length).to eq(csv_data.length + 1)
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
        expect(rows[1][3]).to eq('GenericWork')
        expect(rows[1][4]).to eq('id-001')
        expect(rows[1][5]).to eq('My Title')
      end

      it 'puts the error category in column 3' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        expect(rows[1][2]).to eq('missing_required_value')
      end

      it 'includes clean rows with a blank errors cell' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        clean_row = rows.find { |r| r[4] == 'id-002' }
        expect(clean_row).not_to be_nil
        expect(clean_row[1]).to be_nil
        expect(clean_row[2]).to be_nil
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
        expect(rows[3][1]).to eq('Title is required | Description is required')
      end

      it 'deduplicates the category column when multiple errors share a category' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        expect(rows[3][2]).to eq('missing_required_value')
      end
    end

    context 'when row errors have distinct categories' do
      let(:row_errors) do
        [
          { row: 2, severity: 'warning', category: 'existing_source_identifier', column: 'source_identifier', value: 'id-001', message: 'Exists' },
          { row: 2, severity: 'warning', category: 'default_work_type_used', column: 'model', value: nil, message: 'Using default' }
        ]
      end

      it 'joins distinct category values with " | " in the categories column' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        expect(rows[1][2]).to eq('existing_source_identifier | default_work_type_used')
      end
    end

    context 'when errors span multiple rows' do
      let(:row_errors) do
        [
          { row: 2, severity: 'error', category: 'duplicate_source_identifier', column: 'source_identifier', value: 'id-001', message: 'Duplicate source_identifier' },
          { row: 4, severity: 'warning', category: 'missing_required_value', column: 'title', value: nil, message: 'Title is required' }
        ]
      end

      it 'includes all data rows' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        expect(rows.length).to eq(csv_data.length + 1)
      end

      it 'outputs rows in original order with errors on the correct rows' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        row_by_id = rows[1..].index_by { |r| r[4] }
        expect(row_by_id['id-001'][1]).to eq('Duplicate source_identifier')
        expect(row_by_id['id-003'][1]).to eq('Title is required')
        expect(row_by_id['id-002'][1]).to be_nil
      end
    end

    context 'header row' do
      let(:row_errors) { [{ row: 2, severity: 'error', category: 'test', column: 'title', value: nil, message: 'Error' }] }

      it 'has "row", "errors", and "categories" as the first three columns' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        expect(rows.first[0]).to eq('row')
        expect(rows.first[1]).to eq('errors')
        expect(rows.first[2]).to eq('categories')
      end

      it 'preserves the original headers after the row, errors, and categories columns' do
        result = described_class.build(headers: headers, csv_data: csv_data, row_errors: row_errors)
        rows = CSV.parse(result)
        expect(rows.first[3..]).to eq(headers)
      end
    end

    context 'file-level errors' do
      let(:row_errors) { [] }

      it 'emits a row for each missing required column' do
        result = described_class.build(
          headers: headers, csv_data: csv_data, row_errors: row_errors,
          file_errors: { missing_required: [{ model: 'GenericWork', field: 'title' }] }
        )
        rows = CSV.parse(result)
        expect(rows[1][0]).to be_nil
        expect(rows[1][1]).to eq("Missing required column 'title' (GenericWork)")
      end

      it 'emits a row for each unrecognized header, with suggestion when present' do
        result = described_class.build(
          headers: headers, csv_data: csv_data, row_errors: row_errors,
          file_errors: { unrecognized: { 'legacy_id' => 'identifier', 'notes' => nil } }
        )
        rows = CSV.parse(result)
        messages = rows[1..].map { |r| r[1] }
        expect(messages).to include("Unrecognized column 'legacy_id' (did you mean 'identifier'?)")
        expect(messages).to include("Unrecognized column 'notes'")
      end

      it 'emits a row for each empty column position' do
        result = described_class.build(
          headers: headers, csv_data: csv_data, row_errors: row_errors,
          file_errors: { empty_columns: [3] }
        )
        rows = CSV.parse(result)
        expect(rows[1][1]).to eq('Column 5 has no header and will be ignored during import')
      end

      it 'emits a row for each missing file' do
        result = described_class.build(
          headers: headers, csv_data: csv_data, row_errors: row_errors,
          file_errors: { missing_files: ['photo.jpg'] }
        )
        rows = CSV.parse(result)
        expect(rows[1][1]).to eq('Missing file: photo.jpg')
      end

      it 'leaves the row number blank for file-level rows' do
        result = described_class.build(
          headers: headers, csv_data: csv_data, row_errors: row_errors,
          file_errors: { missing_files: ['photo.jpg'] }
        )
        rows = CSV.parse(result)
        expect(rows[1][0]).to be_nil
      end

      it 'leaves the category cell blank for file-level rows' do
        result = described_class.build(
          headers: headers, csv_data: csv_data, row_errors: row_errors,
          file_errors: { missing_files: ['photo.jpg'] }
        )
        rows = CSV.parse(result)
        expect(rows[1][2]).to be_nil
      end

      it 'leaves data columns blank for file-level rows' do
        result = described_class.build(
          headers: headers, csv_data: csv_data, row_errors: row_errors,
          file_errors: { missing_files: ['photo.jpg'] }
        )
        rows = CSV.parse(result)
        expect(rows[1][3..]).to all(be_nil)
      end

      context 'when both file-level and row-level errors are present' do
        let(:row_errors) { [{ row: 2, severity: 'error', category: 'test', column: 'title', value: nil, message: 'Row error' }] }

        it 'outputs file-level rows before row-level rows' do
          result = described_class.build(
            headers: headers, csv_data: csv_data, row_errors: row_errors,
            file_errors: { missing_required: [{ model: 'GenericWork', field: 'title' }] }
          )
          rows = CSV.parse(result)
          expect(rows[1][0]).to be_nil   # file-level row has no row number
          expect(rows[2][0]).to eq('2')  # row-level row has row number
        end
      end
    end
  end
end
