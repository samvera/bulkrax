# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::ChildReference do
  def make_context(all_ids: Set.new(%w[col1 work1]))
    { errors: [], warnings: [], all_ids: all_ids, parent_split_pattern: nil }
  end

  def make_record(children: nil)
    { source_identifier: 'col1', model: 'Collection', children: children, raw_row: {} }
  end

  it 'adds no error when children field is blank' do
    context = make_context
    described_class.call(make_record(children: nil), 2, context)
    expect(context[:errors]).to be_empty
  end

  it 'adds no error when the child exists in the CSV' do
    context = make_context
    described_class.call(make_record(children: 'work1'), 2, context)
    expect(context[:errors]).to be_empty
  end

  it 'adds an error when the child does not exist in the CSV' do
    context = make_context
    described_class.call(make_record(children: 'missing_child'), 2, context)
    expect(context[:errors].length).to eq(1)
    expect(context[:errors].first[:category]).to eq('invalid_child_reference')
    expect(context[:errors].first[:value]).to eq('missing_child')
  end

  it 'adds an error for each unresolvable id in a pipe-separated list' do
    context = make_context
    described_class.call(make_record(children: 'work1|missing1|missing2'), 2, context)
    expect(context[:errors].length).to eq(2)
    expect(context[:errors].map { |e| e[:value] }).to contain_exactly('missing1', 'missing2')
  end

  context 'when fill_in_blank_source_identifiers is configured and all_ids is empty' do
    before do
      allow(Bulkrax).to receive(:fill_in_blank_source_identifiers)
        .and_return(->(_parser, _index) { SecureRandom.uuid })
    end

    it 'skips the check — child ids cannot be validated against generated identifiers' do
      context = make_context(all_ids: Set.new)
      described_class.call(make_record(children: 'bcd123'), 2, context)
      expect(context[:errors]).to be_empty
    end
  end
end
