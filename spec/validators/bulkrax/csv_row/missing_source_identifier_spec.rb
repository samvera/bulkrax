# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::MissingSourceIdentifier do
  def make_context
    { errors: [], warnings: [], source_identifier: 'source_identifier' }
  end

  def make_record(source_id)
    { source_identifier: source_id, model: 'GenericWork', parent: nil, children: nil, file: nil, raw_row: {} }
  end

  context 'when fill_in_blank_source_identifiers is not configured' do
    before { allow(Bulkrax).to receive(:fill_in_blank_source_identifiers).and_return(nil) }

    it 'adds no error when source_identifier is present' do
      context = make_context
      described_class.call(make_record('work1'), 2, context)
      expect(context[:errors]).to be_empty
    end

    it 'adds an error when source_identifier is blank' do
      context = make_context
      described_class.call(make_record(nil), 2, context)
      expect(context[:errors].length).to eq(1)
      error = context[:errors].first
      expect(error[:category]).to eq('missing_source_identifier')
      expect(error[:row]).to eq(2)
      expect(error[:column]).to eq('source_identifier')
    end

    it 'adds an error when source_identifier is an empty string' do
      context = make_context
      described_class.call(make_record(''), 2, context)
      expect(context[:errors].length).to eq(1)
    end

    it 'uses the source_identifier label from context' do
      context = make_context.merge(source_identifier: 'source_id')
      described_class.call(make_record(nil), 2, context)
      expect(context[:errors].first[:column]).to eq('source_id')
    end
  end

  context 'when fill_in_blank_source_identifiers is configured' do
    before do
      allow(Bulkrax).to receive(:fill_in_blank_source_identifiers)
        .and_return(->(_parser, _index) { SecureRandom.uuid })
    end

    it 'adds no error even when source_identifier is blank' do
      context = make_context
      described_class.call(make_record(nil), 2, context)
      expect(context[:errors]).to be_empty
    end
  end
end
