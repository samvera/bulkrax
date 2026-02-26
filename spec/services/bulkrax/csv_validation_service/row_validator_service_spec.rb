# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvValidationService::RowValidatorService do
  let(:mapping_manager) { instance_double(Bulkrax::CsvValidationService::MappingManager) }

  let(:field_metadata) do
    {
      'GenericWork' => {
        properties: %w[title creator description],
        required_terms: %w[title],
        controlled_vocab_terms: []
      },
      'Collection' => {
        properties: %w[title description],
        required_terms: %w[title],
        controlled_vocab_terms: []
      }
    }
  end

  let(:csv_data) do
    [
      {
        source_identifier: 'work1',
        model: 'GenericWork',
        parent: nil,
        children: nil,
        raw_row: { 'title' => 'Work 1' }
      },
      {
        source_identifier: 'work2',
        model: 'GenericWork',
        parent: 'col1',
        children: nil,
        raw_row: { 'title' => 'Work 2' }
      },
      {
        source_identifier: 'col1',
        model: 'Collection',
        parent: nil,
        children: nil,
        raw_row: { 'title' => 'Collection 1' }
      }
    ]
  end

  before do
    allow(mapping_manager).to receive(:find_by_flag).with(:source_identifier, nil).and_return('source_identifier')
  end

  describe '#errors' do
    it 'returns empty array when data is valid' do
      validator = described_class.new(csv_data, field_metadata, mapping_manager)
      expect(validator.errors).to be_empty
    end

    it 'returns empty array for empty csv data' do
      validator = described_class.new([], field_metadata, mapping_manager)
      expect(validator.errors).to be_empty
    end

    context 'duplicate source_identifier' do
      let(:data_with_duplicate) do
        csv_data + [{
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: { 'title' => 'Duplicate Work' }
        }]
      end

      it 'returns a duplicate_source_identifier error' do
        validator = described_class.new(data_with_duplicate, field_metadata, mapping_manager)
        expect(validator.errors).to include(
          hash_including(
            category: 'duplicate_source_identifier',
            severity: 'error',
            column: 'source_identifier',
            value: 'work1'
          )
        )
      end

      it 'includes the row number in the error' do
        validator = described_class.new(data_with_duplicate, field_metadata, mapping_manager)
        error = validator.errors.find { |e| e[:category] == 'duplicate_source_identifier' }
        expect(error[:row]).to be_present
      end

      it 'includes a human readable message mentioning the identifier' do
        validator = described_class.new(data_with_duplicate, field_metadata, mapping_manager)
        error = validator.errors.find { |e| e[:category] == 'duplicate_source_identifier' }
        expect(error[:message]).to include('work1')
      end

      it 'reports an error for each duplicate occurrence' do
        data_with_multiple_dupes = csv_data + [
          { source_identifier: 'work1', model: 'GenericWork', parent: nil, children: nil, raw_row: { 'title' => 'Dupe 1' } },
          { source_identifier: 'work1', model: 'GenericWork', parent: nil, children: nil, raw_row: { 'title' => 'Dupe 2' } }
        ]
        validator = described_class.new(data_with_multiple_dupes, field_metadata, mapping_manager)
        duplicate_errors = validator.errors.select { |e| e[:category] == 'duplicate_source_identifier' }
        expect(duplicate_errors.length).to eq(2)
      end

      it 'uses the source_identifier column name from the mapping manager' do
        allow(mapping_manager).to receive(:find_by_flag).with(:source_identifier, nil).and_return('source_id')
        validator = described_class.new(data_with_duplicate, field_metadata, mapping_manager)
        error = validator.errors.find { |e| e[:category] == 'duplicate_source_identifier' }
        expect(error[:column]).to eq('source_id')
      end

      it 'falls back to source_identifier when no mapping manager provided' do
        validator = described_class.new(data_with_duplicate, field_metadata, nil)
        error = validator.errors.find { |e| e[:category] == 'duplicate_source_identifier' }
        expect(error[:column]).to eq('source_identifier')
      end
    end

    context 'invalid parent reference' do
      let(:data_with_bad_parent) do
        csv_data + [{
          source_identifier: 'work3',
          model: 'GenericWork',
          parent: 'col-does-not-exist',
          children: nil,
          raw_row: { 'title' => 'Work 3' }
        }]
      end

      it 'returns an invalid_parent_reference error' do
        validator = described_class.new(data_with_bad_parent, field_metadata, mapping_manager)
        expect(validator.errors).to include(
          hash_including(
            category: 'invalid_parent_reference',
            severity: 'error',
            column: 'parent',
            value: 'col-does-not-exist'
          )
        )
      end

      it 'includes the row number in the error' do
        validator = described_class.new(data_with_bad_parent, field_metadata, mapping_manager)
        error = validator.errors.find { |e| e[:category] == 'invalid_parent_reference' }
        expect(error[:row]).to be_present
      end

      it 'includes a human readable message mentioning the missing identifier' do
        validator = described_class.new(data_with_bad_parent, field_metadata, mapping_manager)
        error = validator.errors.find { |e| e[:category] == 'invalid_parent_reference' }
        expect(error[:message]).to include('col-does-not-exist')
      end

      it 'does not error when parent exists in the csv' do
        validator = described_class.new(csv_data, field_metadata, mapping_manager)
        parent_errors = validator.errors.select { |e| e[:category] == 'invalid_parent_reference' }
        expect(parent_errors).to be_empty
      end

      it 'handles pipe-delimited parents and errors only on missing ones' do
        data_with_mixed_parents = csv_data + [{
          source_identifier: 'work3',
          model: 'GenericWork',
          parent: 'col1|col-missing',
          children: nil,
          raw_row: { 'title' => 'Work 3' }
        }]
        validator = described_class.new(data_with_mixed_parents, field_metadata, mapping_manager)
        parent_errors = validator.errors.select { |e| e[:category] == 'invalid_parent_reference' }
        expect(parent_errors.length).to eq(1)
        expect(parent_errors.first[:value]).to eq('col-missing')
      end

      it 'handles multiple invalid pipe-delimited parents' do
        data_with_bad_parents = csv_data + [{
          source_identifier: 'work3',
          model: 'GenericWork',
          parent: 'missing1|missing2',
          children: nil,
          raw_row: { 'title' => 'Work 3' }
        }]
        validator = described_class.new(data_with_bad_parents, field_metadata, mapping_manager)
        parent_errors = validator.errors.select { |e| e[:category] == 'invalid_parent_reference' }
        expect(parent_errors.length).to eq(2)
      end
    end

    context 'missing required value' do
      it 'returns a missing_required_value error when a required field is blank' do
        data_with_missing_title = [{
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: { 'title' => '' }
        }]
        validator = described_class.new(data_with_missing_title, field_metadata, mapping_manager)
        expect(validator.errors).to include(
          hash_including(
            category: 'missing_required_value',
            severity: 'error',
            column: 'title',
            source_identifier: 'work1'
          )
        )
      end

      it 'returns a missing_required_value error when a required field is absent from raw_row' do
        data_with_absent_title = [{
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: {}
        }]
        validator = described_class.new(data_with_absent_title, field_metadata, mapping_manager)
        expect(validator.errors).to include(
          hash_including(
            category: 'missing_required_value',
            severity: 'error',
            column: 'title'
          )
        )
      end

      it 'includes the row number in the error' do
        data = [
          { source_identifier: 'work1', model: 'GenericWork', parent: nil, children: nil, raw_row: { 'title' => 'ok' } },
          { source_identifier: 'work2', model: 'GenericWork', parent: nil, children: nil, raw_row: { 'title' => '' } }
        ]
        validator = described_class.new(data, field_metadata, mapping_manager)
        error = validator.errors.find { |e| e[:category] == 'missing_required_value' }
        expect(error[:row]).to eq(3)
      end

      it 'does not error when required field is present' do
        validator = described_class.new(csv_data, field_metadata, mapping_manager)
        required_errors = validator.errors.select { |e| e[:category] == 'missing_required_value' }
        expect(required_errors).to be_empty
      end

      it 'reports one error per missing required field per row' do
        metadata_with_multiple_required = {
          'GenericWork' => {
            properties: %w[title creator],
            required_terms: %w[title creator],
            controlled_vocab_terms: []
          }
        }
        data = [{
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: {}
        }]
        validator = described_class.new(data, metadata_with_multiple_required, mapping_manager)
        required_errors = validator.errors.select { |e| e[:category] == 'missing_required_value' }
        expect(required_errors.map { |e| e[:column] }).to contain_exactly('title', 'creator')
      end

      it 'does not report missing_required_value when field_metadata is nil' do
        validator = described_class.new(csv_data, nil, mapping_manager)
        required_errors = validator.errors.select { |e| e[:category] == 'missing_required_value' }
        expect(required_errors).to be_empty
      end

      it 'skips required check when model is not in field_metadata' do
        data = [{
          source_identifier: 'work1',
          model: 'UnknownModel',
          parent: nil,
          children: nil,
          raw_row: {}
        }]
        validator = described_class.new(data, field_metadata, mapping_manager)
        required_errors = validator.errors.select { |e| e[:category] == 'missing_required_value' }
        expect(required_errors).to be_empty
      end
    end

    context 'invalid controlled value' do
      let(:field_metadata_with_controlled) do
        {
          'GenericWork' => {
            properties: %w[title creator rights_statement],
            required_terms: %w[title],
            controlled_vocab_terms: %w[rights_statement]
          }
        }
      end

      let(:authority) { instance_double(Qa::Authorities::Local::FileBasedAuthority) }

      before do
        allow(Qa::Authorities::Local).to receive(:subauthority_for).with('rights_statements').and_return(authority)
        allow(Qa::Authorities::Local).to receive(:subauthority_for).with('rights_statement').and_return(authority)
        allow(authority).to receive(:all).and_return([
          { 'label' => 'In Copyright', 'active' => true },
          { 'label' => 'No Copyright', 'active' => true }
        ])
      end

      it 'returns an invalid_controlled_value error when term is not active' do
        allow(authority).to receive(:find).with('Bad Term').and_return({ 'active' => false })

        data = [{
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: { 'title' => 'Work 1', 'rights_statement' => 'Bad Term' }
        }]
        validator = described_class.new(data, field_metadata_with_controlled, mapping_manager)
        expect(validator.errors).to include(
          hash_including(
            category: 'invalid_controlled_value',
            severity: 'error',
            column: 'rights_statement',
            value: 'Bad Term',
            source_identifier: 'work1'
          )
        )
      end

      it 'returns an invalid_controlled_value error when term is not found' do
        allow(authority).to receive(:find).with('Unknown Term').and_return(nil)

        data = [{
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: { 'title' => 'Work 1', 'rights_statement' => 'Unknown Term' }
        }]
        validator = described_class.new(data, field_metadata_with_controlled, mapping_manager)
        expect(validator.errors).to include(
          hash_including(
            category: 'invalid_controlled_value',
            severity: 'error',
            column: 'rights_statement'
          )
        )
      end

      it 'does not error when term is active' do
        allow(authority).to receive(:find).with('In Copyright').and_return({ 'active' => true })

        data = [{
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: { 'title' => 'Work 1', 'rights_statement' => 'In Copyright' }
        }]
        validator = described_class.new(data, field_metadata_with_controlled, mapping_manager)
        controlled_errors = validator.errors.select { |e| e[:category] == 'invalid_controlled_value' }
        expect(controlled_errors).to be_empty
      end

      it 'does not error when term has no active key' do
        allow(authority).to receive(:find).with('Some Term').and_return({ 'id' => 'some-term', 'label' => 'Some Term' })

        data = [{
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: { 'title' => 'Work 1', 'rights_statement' => 'Some Term' }
        }]
        validator = described_class.new(data, field_metadata_with_controlled, mapping_manager)
        controlled_errors = validator.errors.select { |e| e[:category] == 'invalid_controlled_value' }
        expect(controlled_errors).to be_empty
      end

      it 'does not error when controlled field is blank' do
        data = [{
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: { 'title' => 'Work 1', 'rights_statement' => '' }
        }]
        validator = described_class.new(data, field_metadata_with_controlled, mapping_manager)
        controlled_errors = validator.errors.select { |e| e[:category] == 'invalid_controlled_value' }
        expect(controlled_errors).to be_empty
      end

      it 'includes the row number in the error' do
        allow(authority).to receive(:find).with('Bad Term').and_return({ 'active' => false })
        allow(authority).to receive(:find).with('In Copyright').and_return({ 'active' => true })

        data = [
          { source_identifier: 'work1', model: 'GenericWork', parent: nil, children: nil, raw_row: { 'title' => 'Work 1', 'rights_statement' => 'In Copyright' } },
          { source_identifier: 'work2', model: 'GenericWork', parent: nil, children: nil, raw_row: { 'title' => 'Work 2', 'rights_statement' => 'Bad Term' } }
        ]
        validator = described_class.new(data, field_metadata_with_controlled, mapping_manager)
        error = validator.errors.find { |e| e[:category] == 'invalid_controlled_value' }
        expect(error[:row]).to eq(3)
      end

      it 'includes a suggestion when a close match exists' do
        allow(authority).to receive(:find).with('In Copyrigh').and_return({})

        data = [{
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: { 'title' => 'Work 1', 'rights_statement' => 'In Copyrigh' }
        }]
        validator = described_class.new(data, field_metadata_with_controlled, mapping_manager)
        error = validator.errors.find { |e| e[:category] == 'invalid_controlled_value' }
        expect(error[:suggestion]).to include('In Copyright')
      end

      it 'skips controlled vocab check when model has no controlled_vocab_terms' do
        expect(Qa::Authorities::Local).not_to receive(:subauthority_for)

        validator = described_class.new(csv_data, field_metadata, mapping_manager)
        controlled_errors = validator.errors.select { |e| e[:category] == 'invalid_controlled_value' }
        expect(controlled_errors).to be_empty
      end

      it 'skips controlled vocab check when field is not in controlled_vocab_terms for that model' do
        data = [{
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: { 'title' => 'Work 1', 'creator' => 'anything' }
        }]
        validator = described_class.new(data, field_metadata_with_controlled, mapping_manager)
        controlled_errors = validator.errors.select { |e| e[:category] == 'invalid_controlled_value' }
        expect(controlled_errors).to be_empty
      end
    end
  end

  describe '#errors?' do
    it 'returns false when data is valid' do
      validator = described_class.new(csv_data, field_metadata, mapping_manager)
      expect(validator.errors?).to be false
    end

    it 'returns true when there are duplicate source identifiers' do
      data_with_duplicate = csv_data + [{
        source_identifier: 'work1',
        model: 'GenericWork',
        parent: nil,
        children: nil,
        raw_row: { 'title' => 'Dupe' }
      }]
      validator = described_class.new(data_with_duplicate, field_metadata, mapping_manager)
      expect(validator.errors?).to be true
    end

    it 'returns true when there are invalid parent references' do
      data_with_bad_parent = csv_data + [{
        source_identifier: 'work3',
        model: 'GenericWork',
        parent: 'col-does-not-exist',
        children: nil,
        raw_row: { 'title' => 'Work 3' }
      }]
      validator = described_class.new(data_with_bad_parent, field_metadata, mapping_manager)
      expect(validator.errors?).to be true
    end

    it 'returns true when there are missing required values' do
      data_with_missing = [{
        source_identifier: 'work1',
        model: 'GenericWork',
        parent: nil,
        children: nil,
        raw_row: { 'title' => '' }
      }]
      validator = described_class.new(data_with_missing, field_metadata, mapping_manager)
      expect(validator.errors?).to be true
    end
  end

  describe '#valid?' do
    it 'returns true when data is valid' do
      validator = described_class.new(csv_data, field_metadata, mapping_manager)
      expect(validator).to be_valid
    end

    it 'returns false when there are errors' do
      data_with_duplicate = csv_data + [{
        source_identifier: 'work1',
        model: 'GenericWork',
        parent: nil,
        children: nil,
        raw_row: { 'title' => 'Dupe' }
      }]
      validator = described_class.new(data_with_duplicate, field_metadata, mapping_manager)
      expect(validator).not_to be_valid
    end
  end
end
