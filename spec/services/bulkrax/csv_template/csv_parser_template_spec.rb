# frozen_string_literal: true

require 'rails_helper'

# Tests for template generation and validation via CsvParser,
# which replaced CsvValidationService as the entry point.
RSpec.describe Bulkrax::CsvParser do
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
        allow(CSV).to receive(:open).and_return(true)
        allow(FileUtils).to receive(:mkdir_p).and_return(true)

        result = described_class.generate_template(models: ['GenericWork'], output: 'file')
        expect(result.to_s).to be_a(String)
      end

      it 'returns a CSV string when output is csv_string' do
        result = described_class.generate_template(models: ['GenericWork'], output: 'csv_string')
        expect(result).to be_a(String)
      end

      context "with a multi-alias mapping like `file: { from: ['item','file'] }`" do
        before do
          allow(Bulkrax).to receive(:field_mappings).and_return(
            'Bulkrax::CsvParser' => {
              'title' => { 'from' => ['title'] },
              'model' => { 'from' => ['model'] },
              'parents' => { 'from' => ['parents'], 'related_parents_field_mapping' => true },
              'file' => { 'from' => %w[item file] },
              'source_identifier' => { 'from' => ['source_identifier'], 'source_identifier' => true }
            }
          )
        end

        it 'emits one of the file aliases as a column header' do
          template = described_class.generate_template(models: ['GenericWork'], output: 'csv_string')
          headers = template.lines.first.split(',').map(&:strip)
          expect(headers).to include(satisfy { |h| %w[file item].include?(h) })
        end
      end
    end
  end

  describe '.validate_csv' do
    it 'returns validation results hash with expected keys' do
      result = described_class.validate_csv(csv_file: csv_file, zip_file: zip_file)

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
      result = described_class.validate_csv(csv_file: csv_file, zip_file: zip_file)
      expect(result[:headers]).to include('source_identifier', 'title', 'creator', 'model', 'parents', 'file', 'description')
    end

    it 'counts rows correctly' do
      result = described_class.validate_csv(csv_file: csv_file, zip_file: zip_file)
      expect(result[:rowCount]).to eq(4)
    end

    it 'provides hierarchical item information' do
      result = described_class.validate_csv(csv_file: csv_file, zip_file: zip_file)
      expect(result[:works]).to be_an(Array)
      expect(result[:collections]).to be_an(Array)
      expect(result[:fileSets]).to be_an(Array)
      expect(result[:totalItems]).to be_a(Numeric)
    end

    it 'provides file validation information' do
      result = described_class.validate_csv(csv_file: csv_file, zip_file: zip_file)
      expect(result[:fileReferences]).to be_a(Numeric)
      expect(result[:foundFiles]).to be_a(Numeric)
      expect(result[:missingFiles]).to be_an(Array)
      expect(result[:zipIncluded]).to be true
    end

    it 'handles validation without zip file' do
      result = described_class.validate_csv(csv_file: csv_file, zip_file: nil)
      expect(result[:zipIncluded]).to be false
      expect(result[:missingFiles]).to be_empty
      expect(result[:foundFiles]).to eq(0)
    end

    context 'when only rights_statement is missing (suppliable on Step 2)' do
      let(:metadata_only_rights_missing) do
        base = { properties: %w[source_identifier title creator model parents file description], controlled_vocab_terms: [] }
        {
          'GenericWork' => base.merge(required_terms: %w[source_identifier title creator model rights_statement]),
          'Collection' => base.merge(required_terms: %w[source_identifier title])
        }
      end

      before do
        allow(Bulkrax::CsvParser).to receive(:build_validation_field_metadata).and_return(metadata_only_rights_missing)
      end

      it 'treats validation as valid with warnings (isValid: true, hasWarnings: true)' do
        result = described_class.validate_csv(csv_file: csv_file, zip_file: zip_file)
        expect(result[:missingRequired]).to be_present
        expect(result[:missingRequired]).to all(satisfy { |h| h[:field].to_s == 'rights_statement' })
        expect(result[:isValid]).to be true
        expect(result[:hasWarnings]).to be true
      end
    end

    context 'with misspelled headers' do
      let(:csv_content) do
        <<~CSV
          source_idenifier,titel,creater,model,perents,fille,december
          work1,Test Work 1,Author 1,GenericWork,,image1.jpg,A test work
        CSV
      end

      it 'has unrecognized headers' do
        result = described_class.validate_csv(csv_file: csv_file, zip_file: nil)
        expect(result[:unrecognized]).to be_a(Hash)
        expect(result[:unrecognized].keys).to include('source_idenifier', 'titel', 'creater')
      end
    end

    context 'with misspelled suffixed headers' do
      # Pre-2026, headers ending in `_<digits>` were unconditionally accepted
      # regardless of the base name. The validator now requires the base name
      # to be recognised, so a typo like `creater_1` is flagged the same way
      # `creater` (without the suffix) is.
      let(:csv_content) do
        <<~CSV
          source_identifier,title,creater_1,creater_2,model
          work1,Test Work 1,Author 1,Author 2,GenericWork
        CSV
      end

      it 'flags a numbered column whose base name is misspelled' do
        result = described_class.validate_csv(csv_file: csv_file, zip_file: nil)
        expect(result[:unrecognized].keys).to include('creater_1')
      end
    end

    context 'when the parents mapping stores its split under symbol keys' do
      before do
        allow(Bulkrax).to receive(:field_mappings).and_return(
          'Bulkrax::CsvParser' => {
            'title' => { 'from' => ['title'] },
            'model' => { 'from' => ['model'] },
            'parents' => { from: ['parents'], split: '\|', related_parents_field_mapping: true },
            'source_identifier' => { 'from' => ['source_identifier'], 'source_identifier' => true }
          }
        )
      end

      it 'splits a multi-parent cell, as import does' do
        csv = StringIO.new("source_identifier,title,model,parents\nc1,C1,Collection,\nc2,C2,Collection,\nw1,W1,GenericWork,c1|c2\n")
        result = described_class.validate_csv(csv_file: csv)
        expect(result[:rowErrors].map { |e| e[:category] }).not_to include('invalid_parent_reference')
      end
    end

    context 'when the `model` mapping reads an aliased column' do
      before do
        allow(Bulkrax).to receive(:field_mappings).and_return(
          'Bulkrax::CsvParser' => {
            'title' => { 'from' => ['title'] },
            'model' => { 'from' => %w[work_type model] },
            'source_identifier' => { 'from' => ['source_identifier'], 'source_identifier' => true }
          }
        )
      end

      let(:aliased_model_csv) do
        StringIO.new("source_identifier,title,work_type,model\nc1,Coll,Collection,\nw1,Work,,GenericWork\n")
      end

      it 'reads each row model from the first alias with a value, as import does' do
        result = described_class.validate_csv(csv_file: aliased_model_csv)
        expect(result[:collections].map { |c| c[:id] }).to eq(['c1'])
        expect(result[:works].map { |w| w[:id] }).to eq(['w1'])
      end

      it 'takes the last model column with a value, as import does' do
        csv = StringIO.new("source_identifier,title,model,work_type\nx1,X,GenericWork,Collection\n")
        result = described_class.validate_csv(csv_file: csv)
        expect(result[:collections].map { |c| c[:id] }).to eq(['x1'])
      end

      it 'reads a numbered model column without reporting the model column missing' do
        result = described_class.validate_csv(csv_file: StringIO.new("source_identifier,title,work_type_1\nc1,Coll,Collection\n"))
        expect(result[:collections].map { |c| c[:id] }).to eq(['c1'])
        expect(result[:notices]).to all(satisfy { |n| n[:field] != 'model' })
      end

      it 'checks only the models the rows name when an alias column holds them' do
        allow(described_class).to receive(:build_validation_field_metadata).and_call_original
        described_class.validate_csv(csv_file: StringIO.new("source_identifier,title,work_type\nc1,Coll,Collection\n"))
        expect(described_class).to have_received(:build_validation_field_metadata).with(['Collection'], anything)
      end

      it 'does not report the model column as missing' do
        result = described_class.validate_csv(csv_file: StringIO.new("source_identifier,title,work_type\nc1,Coll,Collection\n"))
        expect(result[:notices]).to all(satisfy { |n| n[:field] != 'model' })
      end
    end

    context 'source_identifier generation' do
      context 'when fill_in_blank_source_identifiers is not configured' do
        before { allow(Bulkrax).to receive(:fill_in_blank_source_identifiers).and_return(nil) }

        it 'does not include source_identifier in missingRequired when the column is present' do
          result = described_class.validate_csv(csv_file: csv_file, zip_file: nil)
          source_id_missing = result[:missingRequired].any? { |h| h[:field].to_s == 'source_identifier' }
          expect(source_id_missing).to be false
        end

        it 'treats a missing source_identifier column as an error' do
          csv_without_source_id = Tempfile.new(['no_source_id', '.csv'])
          csv_without_source_id.write("title,model\nTest Work,GenericWork\n")
          csv_without_source_id.rewind

          result = described_class.validate_csv(csv_file: csv_without_source_id, zip_file: nil)
          expect(result[:isValid]).to be false
          expect(result[:missingRequired]).to include(a_hash_including(field: 'source_identifier'))
        ensure
          csv_without_source_id.close
          csv_without_source_id.unlink
        end
      end

      context 'when fill_in_blank_source_identifiers is configured' do
        before do
          allow(Bulkrax).to receive(:fill_in_blank_source_identifiers)
            .and_return(->(_parser, _index) { SecureRandom.uuid })
        end

        it 'does not include source_identifier in missingRequired even when the column is present' do
          result = described_class.validate_csv(csv_file: csv_file, zip_file: nil)
          source_id_missing = result[:missingRequired].any? { |h| h[:field].to_s == 'source_identifier' }
          expect(source_id_missing).to be false
        end

        it 'does not treat a missing source_identifier column as an error' do
          csv_without_source_id = Tempfile.new(['no_source_id', '.csv'])
          csv_without_source_id.write("title,model\nTest Work,GenericWork\n")
          csv_without_source_id.rewind

          result = described_class.validate_csv(csv_file: csv_without_source_id, zip_file: nil)
          expect(result[:isValid]).to be true
          source_id_missing = result[:missingRequired].any? { |h| h[:field].to_s == 'source_identifier' }
          expect(source_id_missing).to be false
        ensure
          csv_without_source_id.close
          csv_without_source_id.unlink
        end
      end
    end
  end

  describe 'TemplateContext' do
    let(:template_context) { Bulkrax::CsvParser::CsvTemplateGeneration::TemplateContext.new(models: ['GenericWork']) }

    it 'initializes with models' do
      expect(template_context.all_models).to eq(['GenericWork'])
    end

    it 'initializes mapping manager' do
      expect(template_context.mappings).to be_a(Hash)
    end

    it 'initializes field analyzer' do
      expect(template_context.field_analyzer).to be_a(Bulkrax::CsvTemplate::FieldAnalyzer)
    end

    describe '#to_csv_string' do
      it 'returns a CSV string' do
        result = template_context.to_csv_string
        expect(result).to be_a(String)
      end
    end

    describe '#to_file' do
      let(:temp_path) { Rails.root.join('tmp', 'test_template.csv') }

      after do
        FileUtils.rm_f(temp_path) if File.exist?(temp_path)
      end

      it 'returns a file path' do
        allow(CSV).to receive(:open).and_return(true)
        allow(FileUtils).to receive(:mkdir_p).and_return(true)
        result = template_context.to_file(file_path: temp_path.to_s)
        expect(result).to eq(temp_path.to_s)
      end
    end

    describe '#field_metadata_for_all_models' do
      it 'returns metadata hash for all models' do
        metadata = template_context.field_metadata_for_all_models
        expect(metadata).to be_a(Hash)
        expect(metadata).to have_key('GenericWork')
        expect(metadata['GenericWork']).to have_key(:properties)
        expect(metadata['GenericWork']).to have_key(:required_terms)
        expect(metadata['GenericWork']).to have_key(:controlled_vocab_terms)
      end
    end
  end
end
