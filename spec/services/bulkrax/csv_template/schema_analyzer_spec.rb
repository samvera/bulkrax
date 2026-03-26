# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvTemplate::SchemaAnalyzer, type: :service do
  describe '#required_terms' do
    context 'when schema is blank' do
      it 'returns an empty array' do
        klass = build_schema_class(schema: nil)
        analyzer = described_class.new(klass: klass)
        expect(analyzer.required_terms).to eq([])
      end
    end

    context 'when schema has required fields' do
      it 'returns only the required field names as strings' do
        required_field = build_field(name: :title, meta: { 'form' => { 'required' => true } })
        optional_field = build_field(name: :description, meta: { 'form' => { 'required' => false } })
        klass = build_schema_class(schema: [required_field, optional_field])
        analyzer = described_class.new(klass: klass)
        expect(analyzer.required_terms).to eq(['title'])
      end
    end

    context 'when field does not respond to meta' do
      it 'excludes that field' do
        field = build_field(name: :title, responds_to_meta: false)
        klass = build_schema_class(schema: [field])
        analyzer = described_class.new(klass: klass)
        expect(analyzer.required_terms).to eq([])
      end
    end
  end

  describe '#controlled_vocab_terms' do
    context 'when schema is nil' do
      it 'returns an empty array' do
        klass = build_schema_class(schema: nil)
        analyzer = described_class.new(klass: klass)
        expect(analyzer.controlled_vocab_terms).to eq([])
      end
    end

    context 'when schema has controlled vocabulary fields' do
      it 'returns the controlled vocabulary field names' do
        controlled_field = build_field(name: :subject, meta: { 'controlled_values' => { 'sources' => ['local'] } })
        regular_field = build_field(name: :title, meta: {})
        klass = build_schema_class(schema: [controlled_field, regular_field])
        analyzer = described_class.new(klass: klass)
        expect(analyzer.controlled_vocab_terms).to eq(['subject'])
      end
    end

    context 'when no controlled properties found, falls back to QA registry' do
      it 'returns fields from the QA registry' do
        klass = build_schema_class(schema: [])
        qa_registry_entry = double(klass: Qa::Authorities::Local::FileBasedAuthority)
        qa_registry = { 'languages' => qa_registry_entry }
        allow(Qa::Authorities::Local).to receive(:registry).and_return(
          double(instance_variable_get: qa_registry)
        )
        analyzer = described_class.new(klass: klass)
        expect(analyzer.controlled_vocab_terms).to eq(['language'])
      end
    end
  end

  describe 'initialization' do
    context 'when klass does not respond to schema' do
      it 'handles gracefully and returns empty arrays' do
        klass = build_schema_class(schema: nil, responds_to_schema: false)
        analyzer = described_class.new(klass: klass)
        expect(analyzer.required_terms).to eq([])
        expect(analyzer.controlled_vocab_terms).to eq([])
      end
    end

    context 'when admin_set_id is provided' do
      before do
        # rubocop:disable Lint/UnusedBlockArgument
        Hyrax.define_singleton_method(:schema_for) { |klass:, admin_set_id: nil| klass.new.singleton_class.schema || klass.schema } unless Hyrax.respond_to?(:schema_for)
        # rubocop:enable Lint/UnusedBlockArgument
      end

      it 'delegates to Hyrax.schema_for and includes context-specific fields' do
        base_field = build_field(name: :title, meta: { 'form' => { 'required' => true } })
        ctx_field  = build_field(name: :dimensions, meta: { 'form' => { 'required' => false } })
        schema = [base_field, ctx_field]
        klass = build_schema_class(schema: [base_field])
        allow(Hyrax).to receive(:schema_for).with(klass: klass, admin_set_id: 'set-123').and_return(schema)
        analyzer = described_class.new(klass: klass, admin_set_id: 'set-123')
        expect(analyzer.required_terms).to eq(['title'])
        expect(Hyrax).to have_received(:schema_for).with(klass: klass, admin_set_id: 'set-123')
      end
    end
  end
end
