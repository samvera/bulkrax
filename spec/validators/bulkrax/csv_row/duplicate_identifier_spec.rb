# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::DuplicateIdentifier do
  def make_context
    { errors: [], warnings: [], seen_ids: {}, source_identifier: 'source_identifier' }
  end

  def make_record(source_id)
    { source_identifier: source_id, model: 'GenericWork', parent: nil, children: nil, file: nil, raw_row: {} }
  end

  it 'adds nothing for a unique identifier' do
    context = make_context
    described_class.call(make_record('work1'), 2, context)
    expect(context[:errors]).to be_empty
    expect(context[:seen_ids]).to eq('work1' => 2)
  end

  it 'records an error for a duplicate identifier' do
    context = make_context
    described_class.call(make_record('work1'), 2, context)
    described_class.call(make_record('work1'), 3, context)

    expect(context[:errors].length).to eq(1)
    error = context[:errors].first
    expect(error[:category]).to eq('duplicate_source_identifier')
    expect(error[:row]).to eq(3)
    expect(error[:value]).to eq('work1')
  end
end
