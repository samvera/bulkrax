# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvValidationService::Validator do
  let(:mapping_manager) { instance_double(Bulkrax::CsvTemplate::MappingManager) }
  let(:file_validator) { nil }

  let(:field_metadata) do
    {
      'Work' => {
        properties: %w[title creator description],
        required_terms: %w[title source_identifier],
        controlled_vocab_terms: []
      },
      'Collection' => {
        properties: %w[title description],
        required_terms: %w[title],
        controlled_vocab_terms: []
      }
    }
  end

  let(:valid_headers) do
    %w[model source_identifier title creator description parent file]
  end

  describe '#unrecognized_headers' do
    context 'with standard headers' do
      it 'returns empty hash when all headers are recognized' do
        csv_headers = %w[title creator description]
        validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

        expect(validator.unrecognized_headers).to be_empty
      end

      it 'identifies unrecognized headers' do
        csv_headers = %w[title creator invalid_field another_bad_one]
        validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

        expect(validator.unrecognized_headers.keys).to contain_exactly('invalid_field', 'another_bad_one')
      end
    end

    context 'with numeric suffixes' do
      it 'recognizes headers with _1 suffix as valid' do
        csv_headers = %w[title_1 creator_1 description_1]
        validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

        expect(validator.unrecognized_headers).to be_empty
      end

      it 'recognizes headers with _2 suffix as valid' do
        csv_headers = %w[title_2 creator_2]
        validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

        expect(validator.unrecognized_headers).to be_empty
      end

      it 'recognizes headers with multi-digit suffixes' do
        csv_headers = %w[title_10 creator_99 description_123]
        validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

        expect(validator.unrecognized_headers).to be_empty
      end

      it 'identifies unrecognized headers even with numeric suffixes' do
        csv_headers = %w[title_1 invalid_field_1 creator_2 another_bad_2]
        validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

        expect(validator.unrecognized_headers.keys).to contain_exactly('invalid_field_1', 'another_bad_2')
      end

      it 'handles mix of suffixed and non-suffixed headers' do
        csv_headers = %w[title title_1 title_2 creator creator_1 description]
        validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

        expect(validator.unrecognized_headers).to be_empty
      end

      it 'does not strip non-numeric suffixes' do
        csv_headers = %w[title_abc creator_xyz]
        validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

        expect(validator.unrecognized_headers.keys).to contain_exactly('title_abc', 'creator_xyz')
      end

      it 'handles underscores in field names correctly' do
        csv_headers = %w[source_identifier source_identifier_1 source_identifier_2]
        validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

        expect(validator.unrecognized_headers).to be_empty
      end
    end

    context 'spell checker suggestions' do
      it 'includes a suggestion when one is available' do
        csv_headers = %w[titel]
        validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

        expect(validator.unrecognized_headers['titel']).to eq('title')
      end

      it 'includes nil when no suggestion is available' do
        csv_headers = %w[zzzznotafield]
        validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

        expect(validator.unrecognized_headers['zzzznotafield']).to be_nil
      end
    end
  end

  describe '#missing_required_fields' do
    before do
      allow(mapping_manager).to receive(:mapped_to_key) { |h| h }
    end

    it 'returns empty array when all required fields are present' do
      csv_headers = %w[title source_identifier model]
      validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

      expect(validator.missing_required_fields).to be_empty
    end

    it 'identifies missing required fields' do
      csv_headers = %w[creator description]
      validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

      missing = validator.missing_required_fields
      expect(missing).to include({ model: 'Work', field: 'title' })
      expect(missing).to include({ model: 'Work', field: 'source_identifier' })
      expect(missing).to include({ model: 'Collection', field: 'title' })
    end

    it 'returns unique missing fields across models' do
      csv_headers = %w[description]
      validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

      missing = validator.missing_required_fields
      title_missing = missing.select { |m| m[:field] == 'title' }

      # Both Work and Collection require title, so we should see 2 entries
      expect(title_missing.length).to eq(2)
    end

    it 'works with mapped column names' do
      allow(mapping_manager).to receive(:mapped_to_key) do |header|
        { 'work_title' => 'title', 'identifier' => 'source_identifier' }[header] || header
      end

      csv_headers = %w[work_title identifier]
      validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

      expect(validator.missing_required_fields).to be_empty
    end

    context 'with numeric suffixes' do
      it 'recognizes title_1 as satisfying title requirement' do
        csv_headers = %w[title_1 source_identifier]
        validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

        expect(validator.missing_required_fields).to be_empty
      end

      it 'recognizes multiple suffixed headers as satisfying requirement' do
        csv_headers = %w[title_1 title_2 source_identifier_1]
        validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

        expect(validator.missing_required_fields).to be_empty
      end

      it 'still identifies missing required fields when suffixed headers do not match' do
        csv_headers = %w[creator_1 description_2]
        validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

        missing = validator.missing_required_fields
        expect(missing).to include({ model: 'Work', field: 'title' })
        expect(missing).to include({ model: 'Work', field: 'source_identifier' })
        expect(missing).to include({ model: 'Collection', field: 'title' })
      end

      it 'works with mix of suffixed and non-suffixed required fields' do
        csv_headers = %w[title source_identifier_1]
        validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

        expect(validator.missing_required_fields).to be_empty
      end
    end
  end

  describe '#errors?' do
    before do
      allow(mapping_manager).to receive(:mapped_to_key) { |h| h }
    end

    it 'returns false when all required fields are present' do
      csv_headers = %w[title source_identifier model]
      validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

      expect(validator.errors?).to be false
    end

    it 'returns true when required fields are missing' do
      csv_headers = %w[description creator]
      validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

      expect(validator.errors?).to be true
    end

    it 'returns true when CSV has no headers' do
      csv_headers = []
      validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

      expect(validator.errors?).to be true
    end
  end

  describe '#valid?' do
    before do
      allow(mapping_manager).to receive(:mapped_to_key) { |h| h }
    end

    it 'returns true when no errors and no warnings' do
      csv_headers = %w[title source_identifier model]
      validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

      expect(validator).to be_valid
    end

    it 'returns false when there are errors (missing required fields)' do
      csv_headers = %w[description creator]
      validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

      expect(validator).not_to be_valid
    end

    it 'returns true with warnings only (unrecognized headers)' do
      csv_headers = %w[title source_identifier model invalid_field]
      validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

      expect(validator).to be_valid
    end

    it 'returns false when there are both errors and warnings' do
      csv_headers = %w[description invalid_field]
      validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

      expect(validator).not_to be_valid
      expect(validator.errors?).to be true
      expect(validator.warnings?).to be true
    end

    it 'returns false when CSV has no headers' do
      csv_headers = []
      validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

      expect(validator).not_to be_valid
    end
  end

  describe '#warnings?' do
    before do
      allow(mapping_manager).to receive(:mapped_to_key) { |h| h }
    end

    it 'returns true when there are unrecognized headers' do
      csv_headers = %w[title creator invalid_field]
      validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

      expect(validator.warnings?).to be true
    end

    it 'returns false when all headers are recognized' do
      csv_headers = %w[title creator description]
      validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager)

      expect(validator.warnings?).to be false
    end

    context 'with file validator' do
      let(:file_validator) do
        instance_double(
          Bulkrax::CsvTemplate::FileValidator,
          possible_missing_files?: has_possible_missing_files
        )
      end

      context 'when files are missing' do
        let(:has_possible_missing_files) { true }

        it 'returns true' do
          csv_headers = %w[title creator]
          validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager, file_validator)

          expect(validator.warnings?).to be true
        end
      end

      context 'when no files are missing' do
        let(:has_possible_missing_files) { false }

        it 'returns false when headers are also valid' do
          csv_headers = %w[title creator]
          validator = described_class.new(csv_headers, valid_headers, field_metadata, mapping_manager, file_validator)

          expect(validator.warnings?).to be false
        end
      end
    end
  end
end
