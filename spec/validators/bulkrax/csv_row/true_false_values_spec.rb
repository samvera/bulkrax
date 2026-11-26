# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::TrueFalseValues do
  subject(:call) { described_class.call(record, 2, context) }

  let(:errors) { [] }
  let(:context) { { errors: errors, mappings: {}, field_metadata: { 'GenericWork' => { true_false_terms: ['hide_from_catalog_search'] } } } }
  let(:record) { { source_identifier: 'work-1', model: 'GenericWork', raw_row: raw_row } }

  context 'with true/false values written any accepted way' do
    let(:raw_row) { { 'hide_from_catalog_search' => 'No', 'delete' => 'FALSE', 'remove_and_rerun' => '' } }

    it 'reports nothing' do
      call
      expect(errors).to be_empty
    end
  end

  context 'with a value that is neither true nor false' do
    let(:raw_row) { { 'hide_from_catalog_search' => 'maybe', 'delete' => 'perhaps' } }

    it 'reports each cell' do
      call
      expect(errors).to contain_exactly(
        hash_including(row: 2, severity: 'error', category: 'invalid_true_false', column: 'hide_from_catalog_search', value: 'maybe'),
        hash_including(row: 2, severity: 'error', category: 'invalid_true_false', column: 'delete', value: 'perhaps')
      )
    end
  end
end
