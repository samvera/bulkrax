# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::RequiredValues do
  def make_context(required_terms: ['title'], notices: [])
    {
      errors: [],
      warnings: [],
      notices: notices,
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

  context 'when model is blank' do
    def make_blank_model_record(raw_row_hash = {})
      {
        source_identifier: 'work1',
        model: nil,
        raw_row: raw_row_hash
      }
    end

    context 'and default_work_type is configured' do
      before do
        allow(Bulkrax).to receive(:default_work_type).and_return('GenericWork')
      end

      it 'emits a default_work_type_used warning' do
        context = make_context
        described_class.call(make_blank_model_record('title' => 'My Title'), 2, context)
        warning = context[:errors].find { |e| e[:category] == 'default_work_type_used' }
        expect(warning).to be_present
        expect(warning[:severity]).to eq('warning')
        expect(warning[:column]).to eq('model')
      end

      it 'also emits a missing_required_value error when a required field is absent' do
        context = make_context
        described_class.call(make_blank_model_record({}), 2, context)
        categories = context[:errors].map { |e| e[:category] }
        expect(categories).to include('default_work_type_used', 'missing_required_value')
      end

      it 'emits only the warning when all required fields are present' do
        context = make_context
        described_class.call(make_blank_model_record('title' => 'My Title'), 2, context)
        expect(context[:errors].map { |e| e[:category] }).to eq(['default_work_type_used'])
      end
    end

    context 'and a file-level notice already covers the missing model column' do
      before { allow(Bulkrax).to receive(:default_work_type).and_return('GenericWork') }

      it 'suppresses the per-row default_work_type_used warning' do
        context = make_context(notices: [{ field: 'model', default_work_type: 'GenericWork' }])
        described_class.call(make_blank_model_record('title' => 'My Title'), 2, context)
        expect(context[:errors]).to be_empty
      end

      it 'still emits missing_required_value errors for blank required fields' do
        context = make_context(notices: [{ field: 'model', default_work_type: 'GenericWork' }])
        described_class.call(make_blank_model_record({}), 2, context)
        expect(context[:errors].map { |e| e[:category] }).to eq(['missing_required_value'])
      end
    end

    context 'and default_work_type is not configured' do
      before do
        allow(Bulkrax).to receive(:default_work_type).and_return(nil)
      end

      it 'adds no errors or warnings (cannot validate without knowing the model)' do
        context = make_context
        described_class.call(make_blank_model_record({}), 2, context)
        expect(context[:errors]).to be_empty
      end
    end
  end

  # When the CSV uses an alias for a required field (e.g. `rights` satisfying
  # `rights_statement` because `rights_statement: { from: ['rights', ...] }`),
  # the validator must honour the mapping — otherwise the header-level check
  # passes but every row still gets flagged as missing the value.
  context 'when the CSV header uses a from: alias for a required field' do
    let(:mapping_manager) do
      mappings = {
        'rights_statement' => { 'from' => ['rights', 'rights_statement', 'rights statement'], 'generated' => true },
        'title' => { 'from' => ['title'] }
      }
      allow(Bulkrax).to receive(:field_mappings).and_return('Bulkrax::CsvParser' => mappings)
      Bulkrax::CsvTemplate::MappingManager.new
    end

    def alias_context
      make_context(required_terms: %w[title rights_statement]).merge(mapping_manager: mapping_manager)
    end

    it 'treats `rights` as satisfying the `rights_statement` requirement' do
      record = make_record('title' => 'My Title', 'rights' => 'http://rightsstatements.org/vocab/CNE/1.0/')
      described_class.call(record, 2, alias_context)
      expect(alias_context[:errors]).to be_empty
    end

    it 'still flags rights_statement as missing when the `rights` column is blank' do
      record = make_record('title' => 'My Title', 'rights' => '')
      context = alias_context
      described_class.call(record, 2, context)
      expect(context[:errors].map { |e| e[:column] }).to contain_exactly('rights_statement')
    end

    it 'falls back to exact-header matching when no mapping_manager is provided' do
      # Back-compat: callers that do not pass a mapping_manager (e.g. existing
      # specs) still work because we short-circuit to the normalised header.
      record = make_record('title' => 'My Title', 'rights_statement' => 'CNE')
      context = make_context(required_terms: %w[title rights_statement])
      described_class.call(record, 2, context)
      expect(context[:errors]).to be_empty
    end
  end
end
