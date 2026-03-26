# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRowValidators::RequiredValues do
  def make_context(required_terms: ['title'])
    {
      errors: [],
      warnings: [],
      field_metadata: { 'GenericWork' => { required_terms: required_terms, controlled_vocab_terms: [] } }
    }
  end

  def make_record(raw_row_hash = {})
    {
      source_identifier: 'work1',
      model: 'GenericWork',
      raw_row: raw_row_hash
    }
  end

  it 'adds no error when the required field is present' do
    context = make_context
    described_class.call(make_record('title' => 'My Title'), 2, context)
    expect(context[:errors]).to be_empty
  end

  it 'adds an error when a required field is missing' do
    context = make_context
    described_class.call(make_record({}), 2, context)
    expect(context[:errors].length).to eq(1)
    expect(context[:errors].first[:category]).to eq('missing_required_value')
    expect(context[:errors].first[:column]).to eq('title')
  end

  it 'accepts a numbered column for a required field (title_1 satisfies title)' do
    context = make_context
    described_class.call(make_record('title_1' => 'My Title'), 2, context)
    expect(context[:errors]).to be_empty
  end
end
