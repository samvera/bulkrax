# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::ParentReference do
  def make_context(all_ids: Set.new(%w[col1 work1]), find_record: nil)
    { errors: [], warnings: [], all_ids: all_ids, parent_split_pattern: nil,
      find_record_by_source_identifier: find_record }
  end

  def make_record(parent: nil)
    { source_identifier: 'work2', model: 'GenericWork', parent: parent, raw_row: {} }
  end

  it 'adds no error when parent field is blank' do
    context = make_context
    described_class.call(make_record(parent: nil), 2, context)
    expect(context[:errors]).to be_empty
  end

  it 'adds no error when the parent exists in the CSV' do
    context = make_context
    described_class.call(make_record(parent: 'col1'), 2, context)
    expect(context[:errors]).to be_empty
  end

  it 'adds an error when the parent does not exist in the CSV' do
    context = make_context
    described_class.call(make_record(parent: 'missing_parent'), 2, context)
    expect(context[:errors].length).to eq(1)
    expect(context[:errors].first[:category]).to eq('invalid_parent_reference')
    expect(context[:errors].first[:value]).to eq('missing_parent')
  end

  it 'adds no error when the parent is not in the CSV but exists as a repository record' do
    find_record = ->(id) { id == 'existing_repo_parent' }
    context = make_context(find_record: find_record)
    described_class.call(make_record(parent: 'existing_repo_parent'), 2, context)
    expect(context[:errors]).to be_empty
  end

  it 'adds an error when the parent is not in the CSV and not found in the repository' do
    find_record = ->(_id) { false }
    context = make_context(find_record: find_record)
    described_class.call(make_record(parent: 'truly_missing'), 2, context)
    expect(context[:errors].length).to eq(1)
    expect(context[:errors].first[:category]).to eq('invalid_parent_reference')
  end
end
