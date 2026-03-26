# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvTemplate::FieldAnalyzer do
  let(:mappings) { { 'title' => { 'from' => ['title'], 'split' => nil } } }
  subject(:analyzer) { described_class.new(mappings) }

  describe '#initialize' do
    it 'initializes with empty field_list' do
      expect(analyzer.field_list).to eq([])
    end

    it 'stores the mappings' do
      expect(analyzer.instance_variable_get(:@mappings)).to eq(mappings)
    end
  end

  describe '#find_or_create_field_list_for' do
    let(:model_name) { 'Work' }
    let(:work_klass) { double('Work') }
    let(:schema_analyzer) { instance_double(Bulkrax::CsvTemplate::SchemaAnalyzer) }

    before do
      allow(Bulkrax::CsvTemplate::ModelLoader).to receive(:determine_klass_for)
        .with('Work').and_return(work_klass)
      allow(Bulkrax::CsvTemplate::SchemaAnalyzer).to receive(:new)
        .with(klass: work_klass, admin_set_id: nil).and_return(schema_analyzer)
      allow(schema_analyzer).to receive(:required_terms).and_return(['title', 'creator'])
      allow(schema_analyzer).to receive(:controlled_vocab_terms).and_return(['rights_statement', 'resource_type'])
    end

    context 'when model has a schema (Valkyrie)' do
      before do
        allow(work_klass).to receive(:respond_to?).and_return(false)
        allow(work_klass).to receive(:respond_to?).with(:schema).and_return(true)
        allow(Bulkrax::ValkyrieObjectFactory).to receive(:schema_properties)
          .with(klass: work_klass, admin_set_id: nil).and_return([:title, :creator, :date_created, :rights_statement])
      end

      it 'creates a new field list entry with schema properties' do
        result = analyzer.find_or_create_field_list_for(model_name: model_name)

        expect(result).to eq({
                               'Work' => {
                                 'properties' => ['title', 'creator', 'date_created', 'rights_statement'],
                                 'required_terms' => ['title', 'creator'],
                                 'controlled_vocab_terms' => ['rights_statement', 'resource_type']
                               }
                             })
      end

      it 'adds the entry to the field_list' do
        analyzer.find_or_create_field_list_for(model_name: model_name)

        expect(analyzer.field_list.size).to eq(1)
        expect(analyzer.field_list.first).to have_key('Work')
      end
    end

    context 'when model uses properties (ActiveFedora)' do
      before do
        allow(work_klass).to receive(:respond_to?).and_return(false)
        allow(work_klass).to receive(:respond_to?).with(:schema).and_return(false)
        allow(work_klass).to receive(:properties).and_return({
                                                               'title' => {},
                                                               'creator' => {},
                                                               'subject' => {},
                                                               'description' => {}
                                                             })
      end

      it 'creates a new field list entry with properties keys' do
        result = analyzer.find_or_create_field_list_for(model_name: model_name)

        expect(result).to eq({
                               'Work' => {
                                 'properties' => ['title', 'creator', 'subject', 'description'],
                                 'required_terms' => ['title', 'creator'],
                                 'controlled_vocab_terms' => ['rights_statement', 'resource_type']
                               }
                             })
      end
    end

    context 'when entry already exists' do
      let(:existing_entry) do
        {
          'Work' => {
            'properties' => ['existing_title'],
            'required_terms' => ['existing_required'],
            'controlled_vocab_terms' => ['existing_controlled']
          }
        }
      end

      before do
        analyzer.instance_variable_set(:@field_list, [existing_entry])
      end

      it 'returns the existing entry without creating a new one' do
        result = analyzer.find_or_create_field_list_for(model_name: model_name)

        expect(result).to eq(existing_entry)
        expect(analyzer.field_list.size).to eq(1)
      end

      it 'does not call ModelLoader or SchemaAnalyzer' do
        expect(Bulkrax::CsvTemplate::ModelLoader).not_to receive(:determine_klass_for)
        expect(Bulkrax::CsvTemplate::SchemaAnalyzer).not_to receive(:new)

        analyzer.find_or_create_field_list_for(model_name: model_name)
      end
    end

    context 'when model class cannot be determined' do
      before do
        allow(Bulkrax::CsvTemplate::ModelLoader).to receive(:determine_klass_for)
          .with('UnknownModel').and_return(nil)
      end

      it 'returns an empty hash' do
        result = analyzer.find_or_create_field_list_for(model_name: 'UnknownModel')

        expect(result).to eq({})
      end
    end
  end

  describe '#controlled_vocab_terms' do
    context 'with no field list entries' do
      it 'returns an empty array' do
        expect(analyzer.controlled_vocab_terms).to eq([])
      end
    end

    context 'with multiple models in field list' do
      before do
        analyzer.instance_variable_set(:@field_list, [
                                         {
                                           'Work' => {
                                             'controlled_vocab_terms' => ['rights_statement', 'resource_type']
                                           }
                                         },
                                         {
                                           'Collection' => {
                                             'controlled_vocab_terms' => ['visibility', 'rights_statement']
                                           }
                                         }
                                       ])
      end

      it 'returns unique controlled vocab terms from all models' do
        expect(analyzer.controlled_vocab_terms).to contain_exactly(
          'rights_statement', 'resource_type', 'visibility'
        )
      end
    end
  end
end
