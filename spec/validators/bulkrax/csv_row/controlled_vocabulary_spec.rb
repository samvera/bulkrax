# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::ControlledVocabulary do
  subject(:call) { described_class.call(record, row_index, context) }

  let(:row_index) { 2 }
  let(:errors) { [] }
  let(:field_metadata) do
    {
      'GenericWork' => {
        required_terms: [],
        controlled_vocab_terms: ['rights_statement']
      }
    }
  end
  let(:context) { { errors: errors, field_metadata: field_metadata } }

  let(:authority) do
    double('authority',
           find: nil,
           all: [
             { 'label' => 'In Copyright', 'active' => true },
             { 'label' => 'No Copyright', 'active' => true },
             { 'label' => 'Deprecated Term', 'active' => false }
           ])
  end

  before do
    allow(described_class).to receive(:load_authority).with('rights_statement').and_return(authority)
  end

  describe '.call' do
    context 'when the value is valid and active' do
      before { allow(authority).to receive(:find).with('In Copyright').and_return({ 'active' => true }) }

      let(:record) do
        {
          source_identifier: 'work-001',
          model: 'GenericWork',
          raw_row: { 'rights_statement' => 'In Copyright' }
        }
      end

      it 'appends no errors' do
        call
        expect(errors).to be_empty
      end
    end

    context 'when the value is not found in the authority' do
      before { allow(authority).to receive(:find).with('Unknown').and_return(nil) }

      let(:record) do
        {
          source_identifier: 'work-001',
          model: 'GenericWork',
          raw_row: { 'rights_statement' => 'Unknown' }
        }
      end

      it 'appends an invalid_controlled_value error' do
        call
        expect(errors.length).to eq(1)
        expect(errors.first).to include(
          row: 2,
          source_identifier: 'work-001',
          severity: 'error',
          category: 'invalid_controlled_value',
          column: 'rights_statement',
          value: 'Unknown'
        )
      end
    end

    context 'when the value is found but inactive' do
      before { allow(authority).to receive(:find).with('Deprecated Term').and_return({ 'active' => false }) }

      let(:record) do
        {
          source_identifier: 'work-001',
          model: 'GenericWork',
          raw_row: { 'rights_statement' => 'Deprecated Term' }
        }
      end

      it 'appends an invalid_controlled_value error' do
        call
        expect(errors.length).to eq(1)
        expect(errors.first[:category]).to eq('invalid_controlled_value')
      end
    end

    context 'when the controlled vocab field is blank' do
      let(:record) do
        {
          source_identifier: 'work-001',
          model: 'GenericWork',
          raw_row: { 'rights_statement' => '' }
        }
      end

      it 'appends no errors' do
        call
        expect(errors).to be_empty
      end
    end

    context 'when the controlled vocab field is absent from the row' do
      let(:record) do
        {
          source_identifier: 'work-001',
          model: 'GenericWork',
          raw_row: {}
        }
      end

      it 'appends no errors' do
        call
        expect(errors).to be_empty
      end
    end

    context 'when no authority is registered for the field' do
      before { allow(described_class).to receive(:load_authority).with('rights_statement').and_return(nil) }

      let(:record) do
        {
          source_identifier: 'work-001',
          model: 'GenericWork',
          raw_row: { 'rights_statement' => 'Anything' }
        }
      end

      it 'appends no errors' do
        call
        expect(errors).to be_empty
      end
    end

    context 'when field_metadata is blank' do
      let(:context) { { errors: errors, field_metadata: {} } }
      let(:record) { { source_identifier: 'work-001', model: 'GenericWork', raw_row: { 'rights_statement' => 'X' } } }

      it 'appends no errors' do
        call
        expect(errors).to be_empty
      end
    end

    context 'when the record model has no metadata entry' do
      let(:record) do
        {
          source_identifier: 'work-001',
          model: 'UnknownModel',
          raw_row: { 'rights_statement' => 'In Copyright' }
        }
      end

      it 'appends no errors' do
        call
        expect(errors).to be_empty
      end
    end

    context 'when the value is close to a valid term (spell-check suggestion)' do
      before { allow(authority).to receive(:find).with('In Copyrite').and_return(nil) }

      let(:record) do
        {
          source_identifier: 'work-001',
          model: 'GenericWork',
          raw_row: { 'rights_statement' => 'In Copyrite' }
        }
      end

      it 'includes a suggestion in the error' do
        call
        expect(errors.first[:suggestion]).to be_present
      end
    end
  end
end
