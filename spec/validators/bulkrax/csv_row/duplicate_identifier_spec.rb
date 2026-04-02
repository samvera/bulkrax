# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::DuplicateIdentifier do
  def make_context(find_record: nil)
    { errors: [], warnings: [], seen_ids: {}, source_identifier: 'source_identifier',
      find_record_by_source_identifier: find_record }
  end

  def make_record(source_id)
    { source_identifier: source_id, model: 'GenericWork', parent: nil, children: nil, file: nil, raw_row: {} }
  end

  it 'adds nothing for a unique identifier that does not exist in the repo' do
    context = make_context(find_record: ->(_id) { false })
    described_class.call(make_record('work1'), 2, context)
    expect(context[:errors]).to be_empty
    expect(context[:seen_ids]).to eq('work1' => 2)
  end

  it 'adds a warning for a unique identifier that already exists in the repo' do
    context = make_context(find_record: ->(_id) { true })
    described_class.call(make_record('work1'), 2, context)
    expect(context[:errors].length).to eq(1)
    warning = context[:errors].first
    expect(warning[:severity]).to eq('warning')
    expect(warning[:category]).to eq('existing_source_identifier')
    expect(warning[:row]).to eq(2)
    expect(warning[:value]).to eq('work1')
  end

  it 'adds no warning when find_record is not provided' do
    context = make_context
    described_class.call(make_record('work1'), 2, context)
    expect(context[:errors]).to be_empty
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

  context 'when fill_in_blank_source_identifiers is configured' do
    before do
      allow(Bulkrax).to receive(:fill_in_blank_source_identifiers)
        .and_return(->(_parser, _index) { SecureRandom.uuid })
    end

    it 'skips the duplicate check for blank source_identifiers' do
      context = make_context
      described_class.call(make_record(nil), 2, context)
      described_class.call(make_record(nil), 3, context)

      expect(context[:errors]).to be_empty
    end

    it 'still records an error for duplicate non-blank identifiers' do
      context = make_context
      described_class.call(make_record('work1'), 2, context)
      described_class.call(make_record('work1'), 3, context)

      expect(context[:errors].length).to eq(1)
    end
  end
end
