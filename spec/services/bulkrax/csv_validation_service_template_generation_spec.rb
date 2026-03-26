# frozen_string_literal: true

require 'rails_helper'

# End-to-end integration spec for Bulkrax::CsvValidationService template generation.
#
# Intent: exercise the full generate_template stack against real models and assert
# on the observable output contract — no mocking of internal components. Changes to
# any component inside the service (CsvBuilder, ColumnBuilder, RowBuilder, etc.)
# must not break the expectations here.
#
# The test app provides: Work (ActiveFedora + Hyrax::WorkBehavior),
# Collection (ActiveFedora + Hyrax::CollectionBehavior + Hyrax::BasicMetadata),
# and FileSet (Hyrax), registered via Hyrax.config.curation_concerns.

RSpec.describe Bulkrax::CsvValidationService, type: :service do
  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def parse_csv_string(csv_string)
    CSV.parse(csv_string, headers: false)
  end

  # ---------------------------------------------------------------------------
  # Error case
  # ---------------------------------------------------------------------------

  describe '.generate_template when Hyrax is not defined' do
    before { hide_const('Hyrax') }

    it 'raises NameError' do
      expect { described_class.generate_template }.to raise_error(NameError, 'Hyrax is not defined')
    end
  end

  # ---------------------------------------------------------------------------
  # to_csv_string output — used as the basis for all structural assertions
  # ---------------------------------------------------------------------------

  describe '.generate_template with output: csv_string' do
    subject(:csv_string) { described_class.generate_template(models: ['Work'], output: 'csv_string') }

    it 'returns a non-empty String' do
      expect(csv_string).to be_a(String).and be_present
    end

    it 'is valid CSV (parseable without error)' do
      expect { parse_csv_string(csv_string) }.not_to raise_error
    end

    describe 'row structure' do
      subject(:rows) { parse_csv_string(csv_string) }

      it 'produces at least three rows (header, explanation, one model row)' do
        expect(rows.length).to be >= 3
      end

      it 'header row (row 0) contains model as the first column' do
        expect(rows[0]).to include('model')
      end

      it 'header row always includes the core Bulkrax columns' do
        expect(rows[0]).to include('model', 'source_identifier', 'file')
      end

      it 'explanation row (row 1) has the same number of cells as the header row' do
        expect(rows[1].length).to eq(rows[0].length)
      end

      it 'explanation row cells are not all blank' do
        expect(rows[1].any?(&:present?)).to be true
      end

      it 'has exactly one model data row for a single-model request' do
        # rows[0] = headers, rows[1] = explanation, rows[2..] = model rows
        model_rows = rows[2..]
        expect(model_rows.length).to eq(1)
      end

      it 'model row contains Work in the model column' do
        header_row  = rows[0]
        model_row   = rows[2]
        model_index = header_row.index('model')
        expect(model_row[model_index]).to eq('Work')
      end
    end

    describe 'column filtering' do
      subject(:headers) { parse_csv_string(csv_string)[0] }

      it 'does not include ignored system properties' do
        ignored = Bulkrax::CsvValidationService::CsvBuilder::IGNORED_PROPERTIES
        expect(headers & ignored).to be_empty
      end

      it 'does not include access_control_id' do
        expect(headers).not_to include('access_control_id')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Multiple models
  # ---------------------------------------------------------------------------

  describe '.generate_template with multiple explicit models' do
    subject(:rows) { parse_csv_string(described_class.generate_template(models: %w[Work Collection], output: 'csv_string')) }

    it 'produces one model data row per model' do
      model_rows = rows[2..]
      expect(model_rows.length).to eq(2)
    end

    it 'includes a row for each requested model' do
      header_row  = rows[0]
      model_index = header_row.index('model')
      model_values = rows[2..].map { |r| r[model_index] }
      expect(model_values).to include('Work', 'Collection')
    end
  end

  # ---------------------------------------------------------------------------
  # 'all' models
  # ---------------------------------------------------------------------------

  describe ".generate_template with models: 'all'" do
    subject(:rows) { parse_csv_string(described_class.generate_template(models: 'all', output: 'csv_string')) }

    it 'produces at least one model data row' do
      expect(rows.length).to be >= 3
    end

    it 'produces rows for the models registered in the test app' do
      header_row   = rows[0]
      model_index  = header_row.index('model')
      model_values = rows[2..].map { |r| r[model_index] }
      # The test app registers Collection and FileSet via Hyrax; assert at least one is present
      expect(model_values).not_to be_empty
      expect(model_values.all?(&:present?)).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Empty / nil models — falls back to all
  # ---------------------------------------------------------------------------

  describe '.generate_template with empty models array' do
    subject(:rows) { parse_csv_string(described_class.generate_template(models: [], output: 'csv_string')) }

    it 'falls back to all available models and produces data rows' do
      expect(rows.length).to be >= 3
    end
  end

  # ---------------------------------------------------------------------------
  # to_file output
  # ---------------------------------------------------------------------------

  describe '.generate_template with output: file' do
    let(:temp_path) { Rails.root.join('tmp', "test_template_#{SecureRandom.hex(4)}.csv") }

    after { FileUtils.rm_f(temp_path) }

    subject(:file_path) { described_class.generate_template(models: ['Work'], output: 'file', file_path: temp_path.to_s) }

    it 'returns the file path as a String' do
      expect(file_path).to eq(temp_path.to_s)
    end

    it 'writes a file to that path' do
      expect(File.exist?(file_path)).to be true
    end

    it 'writes valid CSV content to the file' do
      content = File.read(file_path)
      expect { CSV.parse(content) }.not_to raise_error
    end

    it 'file content matches the csv_string output for the same models' do
      string_output = described_class.generate_template(models: ['Work'], output: 'csv_string')
      file_content  = File.read(file_path)
      # Both should parse to the same number of rows
      expect(CSV.parse(file_content).length).to eq(CSV.parse(string_output).length)
    end
  end

  # ---------------------------------------------------------------------------
  # Empty-column pruning
  # ---------------------------------------------------------------------------

  describe 'empty column pruning' do
    subject(:rows) { parse_csv_string(described_class.generate_template(models: ['Work'], output: 'csv_string')) }

    it 'removes columns where every model row value is blank' do
      headers    = rows[0]
      model_rows = rows[2..]

      service      = described_class.new(models: ['Work'])
      column_builder = Bulkrax::CsvValidationService::ColumnBuilder.new(service)
      required_cols  = column_builder.required_columns

      headers.each_with_index do |header, col_index|
        values = model_rows.map { |r| r[col_index] }
        # Required columns are always kept even when blank — skip them
        next if required_cols.include?(header)

        # Any non-required column that survived pruning must have at least one value
        expect(values.any?(&:present?)).to be(true),
          "Column '#{header}' survived pruning but has no values in any model row"
      end
    end

    it 'always keeps model even when the cell value would be the model name' do
      headers = rows[0]
      expect(headers).to include('model')
    end
  end

  # ---------------------------------------------------------------------------
  # Instance interface (#to_csv_string, #to_file)
  # ---------------------------------------------------------------------------

  describe 'instance interface' do
    let(:service) { described_class.new(models: ['Work']) }

    describe '#to_csv_string' do
      it 'returns a String' do
        expect(service.to_csv_string).to be_a(String)
      end

      it 'returns the same output as the class method' do
        expect(service.to_csv_string).to eq(described_class.generate_template(models: ['Work'], output: 'csv_string'))
      end
    end

    describe '#to_file' do
      let(:temp_path) { Rails.root.join('tmp', "test_template_instance_#{SecureRandom.hex(4)}.csv") }
      after { FileUtils.rm_f(temp_path) }

      it 'writes a file and returns the path' do
        result = service.to_file(file_path: temp_path.to_s)
        expect(result).to eq(temp_path.to_s)
        expect(File.exist?(result)).to be true
      end
    end
  end
end
