# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvValidationService do
  let(:csv_content) do
    <<~CSV
      source_identifier,title,creator,model,parents,file,description
      work1,Test Work 1,Author 1,GenericWork,,image1.jpg,A test work
      work2,Test Work 2,Author 2,GenericWork,col1,,Another work
      col1,Test Collection,,,,,A collection
      fs1,File Set 1,,,work1,document.pdf,A file set
    CSV
  end

  let(:csv_file) do
    file = Tempfile.new(['test', '.csv'])
    file.write(csv_content)
    file.rewind
    file
  end

  let(:zip_file) do
    zip = Tempfile.new(['test', '.zip'])
    Zip::File.open(zip.path, create: true) do |zipfile|
      zipfile.get_output_stream('image1.jpg') { |f| f.write('fake image data') }
      zipfile.get_output_stream('document.pdf') { |f| f.write('fake pdf data') }
    end
    zip.rewind
    zip
  end

  after do
    csv_file.close
    csv_file.unlink
    zip_file.close
    zip_file.unlink
  end

  # Use shared model stubbing helper
  before(:each) do
    stub_bulkrax_models
  end

  describe '.generate_template' do
    context 'when Hyrax is not defined' do
      before { hide_const("Hyrax") }

      it 'raises NameError' do
        expect { described_class.generate_template }.to raise_error(NameError, "Hyrax is not defined")
      end
    end

    context 'when Hyrax is defined' do
      it 'returns a file path when output is file' do
        # Mock the file operations
        allow(CSV).to receive(:open).and_return(true)
        allow(FileUtils).to receive(:mkdir_p).and_return(true)

        result = described_class.generate_template(models: ['GenericWork'], output: 'file')
        expect(result.to_s).to be_a(String)
      end

      it 'returns a CSV string when output is csv_string' do
        result = described_class.generate_template(models: ['GenericWork'], output: 'csv_string')
        expect(result).to be_a(String)
      end
    end
  end

  describe '.validate' do
    it 'returns validation results hash with expected keys' do
      result = described_class.validate(csv_file: csv_file, zip_file: zip_file)

      expect(result).to be_a(Hash)
      expect(result).to have_key(:headers)
      expect(result).to have_key(:missingRequired)
      expect(result).to have_key(:unrecognized)
      expect(result).to have_key(:rowCount)
      expect(result).to have_key(:isValid)
      expect(result).to have_key(:hasWarnings)
      expect(result).to have_key(:collections)
      expect(result).to have_key(:works)
      expect(result).to have_key(:fileSets)
      expect(result).to have_key(:totalItems)
      expect(result).to have_key(:fileReferences)
      expect(result).to have_key(:missingFiles)
      expect(result).to have_key(:foundFiles)
      expect(result).to have_key(:zipIncluded)
    end

    it 'extracts headers from CSV' do
      result = described_class.validate(csv_file: csv_file, zip_file: zip_file)

      expect(result[:headers]).to include('source_identifier', 'title', 'creator', 'model', 'parents', 'file', 'description')
    end

    it 'counts rows correctly' do
      result = described_class.validate(csv_file: csv_file, zip_file: zip_file)

      expect(result[:rowCount]).to eq(4)
    end

    it 'provides hierarchical item information' do
      result = described_class.validate(csv_file: csv_file, zip_file: zip_file)

      expect(result[:works]).to be_an(Array)
      expect(result[:collections]).to be_an(Array)
      expect(result[:fileSets]).to be_an(Array)
      expect(result[:totalItems]).to be_a(Numeric)
    end

    it 'provides file validation information' do
      result = described_class.validate(csv_file: csv_file, zip_file: zip_file)

      expect(result[:fileReferences]).to be_a(Numeric)
      expect(result[:foundFiles]).to be_a(Numeric)
      expect(result[:missingFiles]).to be_an(Array)
      expect(result[:zipIncluded]).to be true
    end

    it 'handles validation without zip file' do
      result = described_class.validate(csv_file: csv_file, zip_file: nil)

      expect(result[:zipIncluded]).to be false
      expect(result[:missingFiles]).to be_empty
      expect(result[:foundFiles]).to eq(0)
    end

    context 'with misspelled headers' do
      let(:csv_content) do
        <<~CSV
          source_idenifier,titel,creater,model,perents,fille,december
          work1,Test Work 1,Author 1,GenericWork,,image1.jpg,A test work
          work2,Test Work 2,Author 2,GenericWork,col1,,Another work
          col1,Test Collection,,,,,A collection
          fs1,File Set 1,,,work1,document.pdf,A file set
        CSV
      end

      it 'has unrecognized headers' do
        result = described_class.validate(csv_file: csv_file, zip_file: nil)

        expect(result[:unrecognized]).to eq({
                                              'source_idenifier' => 'source_identifier',
                                              'titel' => 'title',
                                              'creater' => 'creator',
                                              'perents' => 'parents',
                                              'fille' => 'file',
                                              'december' => nil
                                            })
      end
    end
  end

  describe '#initialize' do
    context 'in generation mode' do
      let(:service) { described_class.new(models: ['GenericWork']) }

      it 'initializes with models' do
        expect(service.all_models).to eq(['GenericWork'])
      end

      it 'initializes mapping manager' do
        expect(service.mappings).to be_a(Hash)
      end

      it 'initializes field analyzer' do
        expect(service.field_analyzer).to be_a(Bulkrax::CsvValidationService::FieldAnalyzer)
      end

      it 'provides mapping_manager accessor' do
        expect(service.mapping_manager).to be_a(Bulkrax::CsvValidationService::MappingManager)
      end
    end

    context 'in validation mode' do
      let(:service) { described_class.new(csv_file: csv_file, zip_file: zip_file) }

      it 'extracts models from CSV' do
        expect(service.all_models).to include('GenericWork')
      end

      it 'provides access to mappings' do
        expect(service.mappings).to be_a(Hash)
      end

      it 'provides access to field analyzer' do
        expect(service.field_analyzer).to be_a(Bulkrax::CsvValidationService::FieldAnalyzer)
      end
    end
  end

  describe '#field_metadata_for_all_models' do
    let(:service) { described_class.new(models: ['GenericWork']) }

    it 'returns metadata hash for all models' do
      metadata = service.field_metadata_for_all_models

      expect(metadata).to be_a(Hash)
      expect(metadata).to have_key('GenericWork')
      expect(metadata['GenericWork']).to have_key(:properties)
      expect(metadata['GenericWork']).to have_key(:required_terms)
      expect(metadata['GenericWork']).to have_key(:controlled_vocab_terms)
    end

    it 'includes properties from the model' do
      metadata = service.field_metadata_for_all_models

      expect(metadata['GenericWork'][:properties]).to include('title', 'creator')
    end
  end

  describe '#valid_headers_for_models' do
    let(:service) { described_class.new(models: ['GenericWork']) }

    it 'returns array of valid header names' do
      headers = service.valid_headers_for_models

      expect(headers).to be_an(Array)
      expect(headers).to include('model')
    end
  end

  describe '#validate' do
    let(:service) { described_class.new(csv_file: csv_file, zip_file: zip_file) }

    it 'returns a hash with validation results' do
      result = service.validate

      expect(result).to be_a(Hash)
      expect(result).to have_key(:isValid)
      expect(result).to have_key(:hasWarnings)
    end

    it 'includes all expected result keys' do
      result = service.validate

      expected_keys = [:headers, :missingRequired, :unrecognized, :rowCount, :isValid, :hasWarnings,
                       :collections, :works, :fileSets, :totalItems,
                       :fileReferences, :missingFiles, :foundFiles, :zipIncluded]

      expected_keys.each do |key|
        expect(result).to have_key(key), "Expected result to have key #{key}"
      end
    end
  end

  describe '#to_csv_string' do
    let(:service) { described_class.new(models: ['GenericWork']) }

    it 'returns a CSV string' do
      result = service.to_csv_string

      expect(result).to be_a(String)
    end
  end

  describe '#to_file' do
    let(:service) { described_class.new(models: ['GenericWork']) }
    let(:temp_path) { Rails.root.join('tmp', 'test_template.csv') }

    after do
      FileUtils.rm_f(temp_path) if File.exist?(temp_path)
    end

    it 'returns a file path' do
      allow(CSV).to receive(:open).and_return(true)
      allow(FileUtils).to receive(:mkdir_p).and_return(true)

      result = service.to_file(file_path: temp_path.to_s)

      expect(result).to eq(temp_path.to_s)
    end
  end
end
