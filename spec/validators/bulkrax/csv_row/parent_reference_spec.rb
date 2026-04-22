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

  context 'split column and suffix columns produce equivalent validation results' do
    it 'reports the same errors whether parents are in one pipe-delimited column or spread across _1/_2 columns' do
      split_context = make_context
      split_record = { source_identifier: 'work2', model: 'GenericWork',
                       parent: 'col1|missing_parent', raw_row: {} }
      described_class.call(split_record, 2, split_context.merge(parent_split_pattern: '|'))

      suffix_context = make_context
      suffix_record = { source_identifier: 'work2', model: 'GenericWork',
                        parent: nil, raw_row: { 'parents_1' => 'col1', 'parents_2' => 'missing_parent' } }
      described_class.call(suffix_record, 2, suffix_context)

      expect(split_context[:errors].map { |e| e.slice(:category, :value) })
        .to eq(suffix_context[:errors].map { |e| e.slice(:category, :value) })
    end
  end

  context 'with numerical suffix columns (parents_1, parents_2)' do
    def make_record_with_suffixes(raw_row: {})
      { source_identifier: 'work2', model: 'GenericWork', parent: nil, raw_row: raw_row }
    end

    it 'adds no error when parents_1 exists in the CSV' do
      context = make_context
      record = make_record_with_suffixes(raw_row: { 'parents_1' => 'col1' })
      described_class.call(record, 2, context)
      expect(context[:errors]).to be_empty
    end

    it 'adds an error when parents_1 references a missing id' do
      context = make_context
      record = make_record_with_suffixes(raw_row: { 'parents_1' => 'missing_parent' })
      described_class.call(record, 2, context)
      expect(context[:errors].length).to eq(1)
      expect(context[:errors].first[:category]).to eq('invalid_parent_reference')
      expect(context[:errors].first[:value]).to eq('missing_parent')
    end

    it 'validates each suffixed column independently' do
      context = make_context
      record = make_record_with_suffixes(raw_row: { 'parents_1' => 'col1', 'parents_2' => 'missing_parent' })
      described_class.call(record, 2, context)
      expect(context[:errors].length).to eq(1)
      expect(context[:errors].first[:value]).to eq('missing_parent')
    end

    it 'adds no error when all suffixed parents resolve via repository lookup' do
      find_record = ->(id) { id == 'repo_parent' }
      context = make_context(find_record: find_record)
      record = make_record_with_suffixes(raw_row: { 'parents_1' => 'col1', 'parents_2' => 'repo_parent' })
      described_class.call(record, 2, context)
      expect(context[:errors]).to be_empty
    end

    it 'ignores raw_row keys that are not suffixed parent columns' do
      context = make_context
      record = make_record_with_suffixes(raw_row: { 'title_1' => 'Some Title', 'parents_1' => 'col1' })
      described_class.call(record, 2, context)
      expect(context[:errors]).to be_empty
    end

    it 'combines base parent field and suffixed columns when both are present' do
      context = make_context
      record = { source_identifier: 'work2', model: 'GenericWork',
                 parent: 'col1', raw_row: { 'parents_2' => 'missing_parent' } }
      described_class.call(record, 2, context)
      expect(context[:errors].length).to eq(1)
      expect(context[:errors].first[:value]).to eq('missing_parent')
    end
  end

  context 'when parent_split_pattern is a Regexp serialised as a String' do
    let(:serialised_split) { '(?-mix:\\s*[;|]\\s*)' }
    let(:all_ids)          { Set.new(%w[coll1 coll2]) }

    it 'splits on | and validates each id individually' do
      context = make_context(all_ids: all_ids).merge(parent_split_pattern: serialised_split)
      record = { source_identifier: 'work2', model: 'GenericWork',
                 parent: 'coll1 | coll2', raw_row: {} }
      described_class.call(record, 2, context)
      expect(context[:errors]).to be_empty
    end

    it 'reports only the missing id when the String regex splits correctly' do
      context = make_context(all_ids: all_ids).merge(parent_split_pattern: serialised_split)
      record = { source_identifier: 'work2', model: 'GenericWork',
                 parent: 'coll1 | missing_parent', raw_row: {} }
      described_class.call(record, 2, context)
      expect(context[:errors].length).to eq(1)
      expect(context[:errors].first[:value]).to eq('missing_parent')
    end
  end
end
