# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::StepperResponseFormatter do
  # Load demo scenarios from the fixtures
  let(:demo_scenarios_path) { File.expand_path('../../fixtures/demo_scenarios.json', __dir__) }
  let(:demo_scenarios) { JSON.parse(File.read(demo_scenarios_path), symbolize_names: true) }

  describe '.format' do
    context 'with success scenarios' do
      it 'formats a perfect validation with no issues' do
        input_data = demo_scenarios[:scenarios][:success_no_issues][:response]
        result = described_class.format(input_data)

        expect(result[:isValid]).to be true
        expect(result[:hasWarnings]).to be false
        expect(result[:messages][:validationStatus][:severity]).to eq('success')
        expect(result[:messages][:validationStatus][:icon]).to eq('fa-check-circle')
        expect(result[:messages][:validationStatus][:title]).to eq('Validation Passed')
        expect(result[:messages][:issues]).to be_empty
      end

      it 'formats validation with all files found in ZIP' do
        input_data = demo_scenarios[:scenarios][:success_with_files][:response]
        result = described_class.format(input_data)

        expect(result[:isValid]).to be true
        expect(result[:hasWarnings]).to be false
        expect(result[:messages][:validationStatus][:severity]).to eq('success')
        expect(result[:messages][:issues].length).to eq(1)

        file_issue = result[:messages][:issues].first
        expect(file_issue[:type]).to eq('file_references')
        expect(file_issue[:severity]).to eq('info')
        expect(file_issue[:count]).to eq(25)
        expect(file_issue[:summary]).to eq('25 of 25 files found in ZIP.')
      end
    end

    context 'with warning scenarios' do
      it 'formats validation with unrecognized fields' do
        input_data = demo_scenarios[:scenarios][:warning_unrecognized][:response]
        result = described_class.format(input_data)

        expect(result[:isValid]).to be true
        expect(result[:hasWarnings]).to be true
        expect(result[:messages][:validationStatus][:severity]).to eq('warning')
        expect(result[:messages][:validationStatus][:icon]).to eq('fa-exclamation-triangle')
        expect(result[:messages][:validationStatus][:title]).to eq('Validation Passed with Warnings')

        unrecognized_issue = result[:messages][:issues].find { |i| i[:type] == 'unrecognized_fields' }
        expect(unrecognized_issue).to be_present
        expect(unrecognized_issue[:severity]).to eq('warning')
        expect(unrecognized_issue[:count]).to eq(2)
        expect(unrecognized_issue[:items].map { |i| i[:field] }).to contain_exactly('legacy_id', 'internal_notes')
      end

      it 'formats validation with missing files from ZIP' do
        input_data = demo_scenarios[:scenarios][:warning_missing_files][:response]
        result = described_class.format(input_data)

        expect(result[:isValid]).to be true
        expect(result[:hasWarnings]).to be true
        expect(result[:messages][:validationStatus][:severity]).to eq('warning')

        file_issue = result[:messages][:issues].find { |i| i[:type] == 'file_references' }
        expect(file_issue).to be_present
        expect(file_issue[:severity]).to eq('warning')
        expect(file_issue[:count]).to eq(55)
        expect(file_issue[:summary]).to eq('52 of 55 files found in ZIP.')
        expect(file_issue[:items].length).to eq(3)
        expect(file_issue[:items].map { |i| i[:field] }).to contain_exactly(
          'photo_087.tiff',
          'letter_scan_12.pdf',
          'recording_03.wav'
        )
      end

      it 'formats validation with file references but no ZIP' do
        input_data = demo_scenarios[:scenarios][:warning_no_zip][:response]
        result = described_class.format(input_data)

        expect(result[:isValid]).to be true
        expect(result[:hasWarnings]).to be true

        file_issue = result[:messages][:issues].find { |i| i[:type] == 'file_references' }
        expect(file_issue).to be_present
        expect(file_issue[:severity]).to eq('warning')
        expect(file_issue[:count]).to eq(30)
        expect(file_issue[:summary]).to eq('30 files referenced in CSV.')
        expect(file_issue[:description]).to include('No ZIP file uploaded')
        expect(file_issue[:items]).to be_empty
      end

      it 'formats validation with combined warnings' do
        input_data = demo_scenarios[:scenarios][:warning_combined][:response]
        result = described_class.format(input_data)

        expect(result[:isValid]).to be true
        expect(result[:hasWarnings]).to be true
        expect(result[:messages][:issues].length).to eq(2)

        unrecognized_issue = result[:messages][:issues].find { |i| i[:type] == 'unrecognized_fields' }
        expect(unrecognized_issue[:count]).to eq(1)

        file_issue = result[:messages][:issues].find { |i| i[:type] == 'file_references' }
        expect(file_issue[:count]).to eq(55)
      end
    end

    context 'with error scenarios' do
      it 'formats validation with missing required fields' do
        input_data = demo_scenarios[:scenarios][:error_missing_required][:response]
        result = described_class.format(input_data)

        expect(result[:isValid]).to be false
        expect(result[:messages][:validationStatus][:severity]).to eq('error')
        expect(result[:messages][:validationStatus][:icon]).to eq('fa-times-circle')
        expect(result[:messages][:validationStatus][:title]).to eq('Validation Failed')
        expect(result[:messages][:validationStatus][:details]).to eq('Critical errors must be fixed before import.')

        missing_issue = result[:messages][:issues].find { |i| i[:type] == 'missing_required_fields' }
        expect(missing_issue).to be_present
        expect(missing_issue[:severity]).to eq('error')
        expect(missing_issue[:count]).to eq(2)
        expect(missing_issue[:items].map { |i| i[:field] }).to contain_exactly('source_identifier', 'model')
      end

      it 'formats validation with combined errors and warnings' do
        input_data = demo_scenarios[:scenarios][:error_combined][:response]
        result = described_class.format(input_data)

        expect(result[:isValid]).to be false
        expect(result[:hasWarnings]).to be true
        expect(result[:messages][:validationStatus][:severity]).to eq('error')
        expect(result[:messages][:issues].length).to eq(2)

        missing_issue = result[:messages][:issues].find { |i| i[:type] == 'missing_required_fields' }
        expect(missing_issue[:severity]).to eq('error')
        expect(missing_issue[:count]).to eq(2)

        unrecognized_issue = result[:messages][:issues].find { |i| i[:type] == 'unrecognized_fields' }
        expect(unrecognized_issue[:severity]).to eq('warning')
        expect(unrecognized_issue[:count]).to eq(1)
      end
    end

    context 'with already formatted data' do
      it 'returns data as-is when it already has messages structure' do
        input_data = demo_scenarios[:scenarios][:success_no_issues][:response]
        result = described_class.format(input_data)

        # Should return the same data since it's already formatted
        expect(result).to eq(input_data)
      end
    end

    context 'with raw validation data' do
      let(:raw_data) do
        {
          headers: ['source_identifier', 'title', 'creator', 'model'],
          missingRequired: [],
          unrecognized: [],
          rowCount: 10,
          isValid: true,
          hasWarnings: false,
          collections: [],
          works: [],
          fileSets: [],
          totalItems: 10,
          fileReferences: 0,
          missingFiles: [],
          foundFiles: 0,
          zipIncluded: false
        }
      end

      it 'formats raw data into proper structure' do
        result = described_class.format(raw_data)

        expect(result[:messages]).to be_present
        expect(result[:messages][:validationStatus]).to be_present
        expect(result[:messages][:issues]).to be_an(Array)
      end

      it 'includes all original data fields' do
        result = described_class.format(raw_data)

        expect(result[:headers]).to eq(raw_data[:headers])
        expect(result[:rowCount]).to eq(raw_data[:rowCount])
        expect(result[:isValid]).to eq(raw_data[:isValid])
        expect(result[:totalItems]).to eq(raw_data[:totalItems])
      end
    end
  end

  describe '.error' do
    it 'generates a default error response' do
      result = described_class.error

      expect(result[:totalItems]).to eq(0)
      expect(result[:collections]).to eq([])
      expect(result[:works]).to eq([])
      expect(result[:fileSets]).to eq([])
      expect(result[:isValid]).to be false
      expect(result[:hasWarnings]).to be false
      expect(result[:messages][:validationStatus][:severity]).to eq('error')
      expect(result[:messages][:validationStatus][:icon]).to eq('fa-times-circle')
      expect(result[:messages][:validationStatus][:title]).to eq('Validation Failed')
      expect(result[:messages][:validationStatus][:summary]).to eq('Unable to process files for validation')
      expect(result[:messages][:issues]).to be_empty
    end

    it 'generates error response with custom message' do
      custom_message = 'Custom error message'
      result = described_class.error(message: custom_message)

      expect(result[:messages][:validationStatus][:summary]).to eq(custom_message)
    end

    it 'generates error response with custom summary' do
      custom_summary = 'Custom summary message'
      result = described_class.error(message: 'Message', summary: custom_summary)

      expect(result[:messages][:validationStatus][:summary]).to eq(custom_summary)
    end
  end

  describe '#format' do
    context 'validation status generation' do
      it 'generates correct summary with column and row counts' do
        data = {
          headers: ['source_identifier', 'title', 'creator'],
          rowCount: 42,
          isValid: true,
          hasWarnings: false,
          unrecognized: [],
          fileReferences: 0
        }

        result = described_class.new(data).format

        expect(result[:messages][:validationStatus][:summary]).to eq('3 columns detected · 42 records found')
      end

      it 'generates details with recognized fields for valid data' do
        data = {
          headers: ['source_identifier', 'title', 'creator', 'unknown_field'],
          rowCount: 10,
          isValid: true,
          hasWarnings: true,
          unrecognized: ['unknown_field'],
          fileReferences: 0
        }

        result = described_class.new(data).format

        expect(result[:messages][:validationStatus][:details]).to eq(
          'Recognized fields: source_identifier, title, creator'
        )
      end

      it 'generates error details for invalid data' do
        data = {
          headers: ['title'],
          rowCount: 5,
          isValid: false,
          hasWarnings: false,
          missingRequired: ['source_identifier', 'model'],
          unrecognized: [],
          fileReferences: 0
        }

        result = described_class.new(data).format

        expect(result[:messages][:validationStatus][:details]).to eq('Critical errors must be fixed before import.')
      end
    end

    context 'issues generation' do
      it 'generates missing required fields issue' do
        data = {
          headers: ['title'],
          rowCount: 5,
          isValid: false,
          hasWarnings: false,
          missingRequired: ['source_identifier', 'model'],
          unrecognized: [],
          fileReferences: 0
        }

        result = described_class.new(data).format
        issue = result[:messages][:issues].find { |i| i[:type] == 'missing_required_fields' }

        expect(issue[:severity]).to eq('error')
        expect(issue[:icon]).to eq('fa-times-circle')
        expect(issue[:title]).to eq('Missing Required Fields')
        expect(issue[:count]).to eq(2)
        expect(issue[:description]).to eq('These required columns must be added to your CSV:')
        expect(issue[:items]).to contain_exactly(
          { field: 'source_identifier', message: 'add this column to your CSV' },
          { field: 'model', message: 'add this column to your CSV' }
        )
      end

      it 'generates unrecognized fields issue' do
        data = {
          headers: ['source_identifier', 'title', 'legacy_id'],
          rowCount: 10,
          isValid: true,
          hasWarnings: true,
          missingRequired: [],
          unrecognized: ['legacy_id'],
          fileReferences: 0
        }

        result = described_class.new(data).format
        issue = result[:messages][:issues].find { |i| i[:type] == 'unrecognized_fields' }

        expect(issue[:severity]).to eq('warning')
        expect(issue[:icon]).to eq('fa-exclamation-triangle')
        expect(issue[:title]).to eq('Unrecognized Fields')
        expect(issue[:count]).to eq(1)
        expect(issue[:description]).to eq('These columns will be ignored during import:')
        expect(issue[:items]).to contain_exactly(
          { field: 'legacy_id', message: nil }
        )
      end

      it 'generates file references issue for missing files in ZIP' do
        data = {
          headers: ['source_identifier', 'title', 'file'],
          rowCount: 10,
          isValid: true,
          hasWarnings: true,
          missingRequired: [],
          unrecognized: [],
          fileReferences: 10,
          foundFiles: 8,
          missingFiles: ['file1.jpg', 'file2.pdf'],
          zipIncluded: true
        }

        result = described_class.new(data).format
        issue = result[:messages][:issues].find { |i| i[:type] == 'file_references' }

        expect(issue[:severity]).to eq('warning')
        expect(issue[:icon]).to eq('fa-info-circle')
        expect(issue[:title]).to eq('File References')
        expect(issue[:count]).to eq(10)
        expect(issue[:summary]).to eq('8 of 10 files found in ZIP.')
        expect(issue[:description]).to eq('2 files referenced in your CSV but missing from the ZIP:')
        expect(issue[:items]).to contain_exactly(
          { field: 'file1.jpg', message: 'missing from ZIP' },
          { field: 'file2.pdf', message: 'missing from ZIP' }
        )
      end

      it 'generates file references issue when no ZIP uploaded' do
        data = {
          headers: ['source_identifier', 'title', 'file'],
          rowCount: 5,
          isValid: true,
          hasWarnings: true,
          missingRequired: [],
          unrecognized: [],
          fileReferences: 5,
          foundFiles: 0,
          missingFiles: [],
          zipIncluded: false
        }

        result = described_class.new(data).format
        issue = result[:messages][:issues].find { |i| i[:type] == 'file_references' }

        expect(issue[:severity]).to eq('warning')
        expect(issue[:icon]).to eq('fa-exclamation-triangle')
        expect(issue[:title]).to eq('File References')
        expect(issue[:count]).to eq(5)
        expect(issue[:summary]).to eq('5 files referenced in CSV.')
        expect(issue[:description]).to eq('No ZIP file uploaded. Ensure files are accessible on the server or upload a ZIP.')
        expect(issue[:items]).to be_empty
      end

      it 'does not generate file references issue when no files are referenced' do
        data = {
          headers: ['source_identifier', 'title'],
          rowCount: 5,
          isValid: true,
          hasWarnings: false,
          missingRequired: [],
          unrecognized: [],
          fileReferences: 0,
          foundFiles: 0,
          missingFiles: [],
          zipIncluded: false
        }

        result = described_class.new(data).format
        issue = result[:messages][:issues].find { |i| i[:type] == 'file_references' }

        expect(issue).to be_nil
      end
    end

    context 'data preservation' do
      it 'preserves collections data' do
        input_data = demo_scenarios[:scenarios][:success_no_issues][:response]
        result = described_class.format(input_data)

        expect(result[:collections]).to eq(input_data[:collections])
        expect(result[:collections].length).to eq(5)
      end

      it 'preserves works data' do
        input_data = demo_scenarios[:scenarios][:success_no_issues][:response]
        result = described_class.format(input_data)

        expect(result[:works]).to eq(input_data[:works])
        expect(result[:works].length).to eq(16)
      end

      it 'preserves fileSets data' do
        input_data = demo_scenarios[:scenarios][:success_no_issues][:response]
        result = described_class.format(input_data)

        expect(result[:fileSets]).to eq(input_data[:fileSets])
        expect(result[:fileSets].length).to eq(3)
      end

      it 'preserves totalItems count' do
        input_data = demo_scenarios[:scenarios][:success_no_issues][:response]
        result = described_class.format(input_data)

        expect(result[:totalItems]).to eq(20)
      end
    end
  end
end
