# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::ChildReference do
  def make_context(all_ids: Set.new(%w[col1 work1]), find_record: nil)
    { errors: [], warnings: [], all_ids: all_ids, parent_split_pattern: nil,
      find_record_by_source_identifier: find_record }
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

  it 'adds no error when the child is not in the CSV but exists as a repository record' do
    find_record = ->(id) { id == 'existing_repo_child' }
    context = make_context(find_record: find_record)
    described_class.call(make_record(children: 'existing_repo_child'), 2, context)
    expect(context[:errors]).to be_empty
  end

  it 'adds an error when the child is not in the CSV and not found in the repository' do
    find_record = ->(_id) { false }
    context = make_context(find_record: find_record)
    described_class.call(make_record(children: 'truly_missing'), 2, context)
    expect(context[:errors].length).to eq(1)
    expect(context[:errors].first[:category]).to eq('invalid_child_reference')
  end

  it 'resolves mixed pipe-separated ids using both CSV and repository lookup' do
    find_record = ->(id) { id == 'repo_child' }
    context = make_context(find_record: find_record)
    described_class.call(make_record(children: 'work1|repo_child|truly_missing'), 2, context)
    expect(context[:errors].length).to eq(1)
    expect(context[:errors].first[:value]).to eq('truly_missing')
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

  context 'split column and suffix columns produce equivalent validation results' do
    it 'reports the same errors whether children are in one pipe-delimited column or spread across _1/_2 columns' do
      split_context = make_context
      split_record = { source_identifier: 'col1', model: 'Collection',
                       children: 'work1|missing_child', raw_row: {} }
      described_class.call(split_record, 2, split_context)

      suffix_context = make_context
      suffix_record = { source_identifier: 'col1', model: 'Collection',
                        children: nil, raw_row: { 'children_1' => 'work1', 'children_2' => 'missing_child' } }
      described_class.call(suffix_record, 2, suffix_context)

      expect(split_context[:errors].map { |e| e.slice(:category, :value) })
        .to eq(suffix_context[:errors].map { |e| e.slice(:category, :value) })
    end
  end

  context 'with numerical suffix columns (children_1, children_2)' do
    def make_record_with_suffixes(raw_row: {})
      { source_identifier: 'col1', model: 'Collection', children: nil, raw_row: raw_row }
    end

    it 'adds no error when children_1 exists in the CSV' do
      context = make_context
      record = make_record_with_suffixes(raw_row: { 'children_1' => 'work1' })
      described_class.call(record, 2, context)
      expect(context[:errors]).to be_empty
    end

    it 'adds an error when children_1 references a missing id' do
      context = make_context
      record = make_record_with_suffixes(raw_row: { 'children_1' => 'missing_child' })
      described_class.call(record, 2, context)
      expect(context[:errors].length).to eq(1)
      expect(context[:errors].first[:category]).to eq('invalid_child_reference')
      expect(context[:errors].first[:value]).to eq('missing_child')
    end

    it 'validates each suffixed column independently' do
      context = make_context
      record = make_record_with_suffixes(raw_row: { 'children_1' => 'work1', 'children_2' => 'missing_child' })
      described_class.call(record, 2, context)
      expect(context[:errors].length).to eq(1)
      expect(context[:errors].first[:value]).to eq('missing_child')
    end

    it 'adds no error when all suffixed children resolve via repository lookup' do
      find_record = ->(id) { id == 'repo_child' }
      context = make_context(find_record: find_record)
      record = make_record_with_suffixes(raw_row: { 'children_1' => 'work1', 'children_2' => 'repo_child' })
      described_class.call(record, 2, context)
      expect(context[:errors]).to be_empty
    end

    it 'ignores raw_row keys that are not suffixed children columns' do
      context = make_context
      record = make_record_with_suffixes(raw_row: { 'title_1' => 'Some Title', 'children_1' => 'work1' })
      described_class.call(record, 2, context)
      expect(context[:errors]).to be_empty
    end

    it 'combines base children field and suffixed columns when both are present' do
      context = make_context
      record = { source_identifier: 'col1', model: 'Collection',
                 children: 'work1', raw_row: { 'children_2' => 'missing_child' } }
      described_class.call(record, 2, context)
      expect(context[:errors].length).to eq(1)
      expect(context[:errors].first[:value]).to eq('missing_child')
    end
  end

  context 'with a configurable split pattern' do
    def make_context_with_split(split_pattern, all_ids: Set.new(%w[col1 work1]))
      { errors: [], warnings: [], all_ids: all_ids, child_split_pattern: split_pattern,
        find_record_by_source_identifier: nil }
    end

    it 'splits on a custom pattern when child_split_pattern is provided' do
      context = make_context_with_split(';')
      described_class.call(make_record(children: 'work1;missing_child'), 2, context)
      expect(context[:errors].length).to eq(1)
      expect(context[:errors].first[:value]).to eq('missing_child')
    end

    it 'falls back to | when child_split_pattern is nil' do
      context = make_context_with_split(nil)
      described_class.call(make_record(children: 'work1|missing_child'), 2, context)
      expect(context[:errors].length).to eq(1)
      expect(context[:errors].first[:value]).to eq('missing_child')
    end
  end

  context 'when child_split_pattern is a Regexp serialised as a String' do
    let(:serialised_split) { '(?-mix:\\s*[;|]\\s*)' }
    let(:all_ids)          { Set.new(%w[col1 work1 work2]) }

    def make_context_with_split(split_pattern)
      { errors: [], warnings: [], all_ids: all_ids, child_split_pattern: split_pattern,
        find_record_by_source_identifier: nil }
    end

    it 'splits on | and validates each id individually' do
      context = make_context_with_split(serialised_split)
      described_class.call(make_record(children: 'work1 | work2'), 2, context)
      expect(context[:errors]).to be_empty
    end

    it 'reports only the missing id when the String regex splits correctly' do
      context = make_context_with_split(serialised_split)
      described_class.call(make_record(children: 'work1 | missing_child'), 2, context)
      expect(context[:errors].length).to eq(1)
      expect(context[:errors].first[:value]).to eq('missing_child')
    end
  end
end
