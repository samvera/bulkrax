# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::SampleCsvService::FieldAnalyzer do
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
    let(:schema_analyzer) { instance_double(Bulkrax::SampleCsvService::SchemaAnalyzer) }

    before do
      allow(Bulkrax::SampleCsvService::ModelLoader).to receive(:determine_klass_for)
        .with('Work').and_return(work_klass)
      allow(Bulkrax::SampleCsvService::SchemaAnalyzer).to receive(:new)
        .with(work_klass).and_return(schema_analyzer)
      allow(schema_analyzer).to receive(:required_terms).and_return(['title', 'creator'])
      allow(schema_analyzer).to receive(:controlled_vocab_terms).and_return(['rights_statement', 'resource_type'])
    end

    context 'when model has a schema (Valkyrie)' do
      before do
        allow(work_klass).to receive(:respond_to?).and_return(false)
        allow(work_klass).to receive(:respond_to?).with(:schema).and_return(true)
        allow(Bulkrax::ValkyrieObjectFactory).to receive(:schema_properties)
          .with(work_klass).and_return([:title, :creator, :date_created, :rights_statement])
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
        expect(Bulkrax::SampleCsvService::ModelLoader).not_to receive(:determine_klass_for)
        expect(Bulkrax::SampleCsvService::SchemaAnalyzer).not_to receive(:new)

        analyzer.find_or_create_field_list_for(model_name: model_name)
      end
    end

    context 'when model class cannot be determined' do
      before do
        allow(Bulkrax::SampleCsvService::ModelLoader).to receive(:determine_klass_for)
          .with('UnknownModel').and_return(nil)
      end

      it 'returns an empty hash' do
        result = analyzer.find_or_create_field_list_for(model_name: 'UnknownModel')

        expect(result).to eq({})
      end

      it 'does not add anything to field_list' do
        analyzer.find_or_create_field_list_for(model_name: 'UnknownModel')

        expect(analyzer.field_list).to be_empty
      end
    end

    context 'with multiple different models' do
      let(:collection_klass) { double('Collection') }
      let(:collection_schema_analyzer) { instance_double(Bulkrax::SampleCsvService::SchemaAnalyzer) }

      before do
        # Setup for Work
        allow(work_klass).to receive(:respond_to?).and_return(false)
        allow(work_klass).to receive(:respond_to?).with(:schema).and_return(true)
        allow(Bulkrax::ValkyrieObjectFactory).to receive(:schema_properties)
          .with(work_klass).and_return([:title, :creator])

        # Setup for Collection
        allow(Bulkrax::SampleCsvService::ModelLoader).to receive(:determine_klass_for)
          .with('Collection').and_return(collection_klass)
        allow(collection_klass).to receive(:respond_to?).and_return(false)
        allow(collection_klass).to receive(:respond_to?).with(:schema).and_return(true)
        allow(Bulkrax::ValkyrieObjectFactory).to receive(:schema_properties)
          .with(collection_klass).and_return([:title, :description])

        allow(Bulkrax::SampleCsvService::SchemaAnalyzer).to receive(:new)
          .with(collection_klass).and_return(collection_schema_analyzer)
        allow(collection_schema_analyzer).to receive(:required_terms).and_return(['title'])
        allow(collection_schema_analyzer).to receive(:controlled_vocab_terms).and_return(['visibility'])
      end

      it 'maintains separate entries for each model' do
        work_result = analyzer.find_or_create_field_list_for(model_name: 'Work')
        collection_result = analyzer.find_or_create_field_list_for(model_name: 'Collection')

        expect(analyzer.field_list.size).to eq(2)
        expect(analyzer.field_list[0]).to have_key('Work')
        expect(analyzer.field_list[1]).to have_key('Collection')

        expect(work_result['Work']['properties']).to eq(['title', 'creator'])
        expect(collection_result['Collection']['properties']).to eq(['title', 'description'])
      end
    end
  end

  describe '#controlled_vocab_terms' do
    context 'with no field list entries' do
      it 'returns an empty array' do
        expect(analyzer.controlled_vocab_terms).to eq([])
      end
    end

    context 'with one model in field list' do
      before do
        analyzer.instance_variable_set(:@field_list, [
                                         {
                                           'Work' => {
                                             'properties' => ['title', 'creator'],
                                             'required_terms' => ['title'],
                                             'controlled_vocab_terms' => ['rights_statement', 'resource_type', 'license']
                                           }
                                         }
                                       ])
      end

      it 'returns controlled vocab terms from that model' do
        expect(analyzer.controlled_vocab_terms).to contain_exactly(
          'rights_statement', 'resource_type', 'license'
        )
      end
    end

    context 'with multiple models in field list' do
      before do
        analyzer.instance_variable_set(:@field_list, [
                                         {
                                           'Work' => {
                                             'properties' => ['title', 'creator'],
                                             'required_terms' => ['title'],
                                             'controlled_vocab_terms' => ['rights_statement', 'resource_type']
                                           }
                                         },
                                         {
                                           'Collection' => {
                                             'properties' => ['title', 'description'],
                                             'required_terms' => ['title'],
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

    context 'with models having no controlled vocab terms' do
      before do
        analyzer.instance_variable_set(:@field_list, [
                                         {
                                           'Work' => {
                                             'properties' => ['title', 'creator'],
                                             'required_terms' => ['title'],
                                             'controlled_vocab_terms' => nil # Could be nil
                                           }
                                         },
                                         {
                                           'Collection' => {
                                             'properties' => ['title', 'description'],
                                             'required_terms' => ['title']
                                             # controlled_vocab_terms key might be missing
                                           }
                                         }
                                       ])
      end

      it 'handles nil and missing controlled_vocab_terms gracefully' do
        expect(analyzer.controlled_vocab_terms).to eq([])
      end
    end

    context 'with duplicate controlled vocab terms across models' do
      before do
        analyzer.instance_variable_set(:@field_list, [
                                         {
                                           'Work' => {
                                             'controlled_vocab_terms' => ['rights_statement', 'resource_type', 'audience']
                                           }
                                         },
                                         {
                                           'Collection' => {
                                             'controlled_vocab_terms' => ['rights_statement', 'audience', 'education_level']
                                           }
                                         },
                                         {
                                           'FileSet' => {
                                             'controlled_vocab_terms' => ['resource_type', 'education_level', 'license']
                                           }
                                         }
                                       ])
      end

      it 'returns unique list without duplicates' do
        result = analyzer.controlled_vocab_terms

        expect(result).to contain_exactly(
          'rights_statement', 'resource_type', 'audience', 'education_level', 'license'
        )
        expect(result.size).to eq(5) # Ensure no duplicates
      end
    end
  end

  describe 'integration scenario' do
    let(:work_klass) { double('Work') }
    let(:collection_klass) { double('Collection') }
    let(:work_schema_analyzer) { instance_double(Bulkrax::SampleCsvService::SchemaAnalyzer) }
    let(:collection_schema_analyzer) { instance_double(Bulkrax::SampleCsvService::SchemaAnalyzer) }

    before do
      # Setup Work
      allow(Bulkrax::SampleCsvService::ModelLoader).to receive(:determine_klass_for)
        .with('Work').and_return(work_klass)
      allow(work_klass).to receive(:respond_to?).and_return(false)
      allow(work_klass).to receive(:respond_to?).with(:schema).and_return(true)
      allow(Bulkrax::ValkyrieObjectFactory).to receive(:schema_properties)
        .with(work_klass).and_return([:title, :creator, :rights_statement])
      allow(Bulkrax::SampleCsvService::SchemaAnalyzer).to receive(:new)
        .with(work_klass).and_return(work_schema_analyzer)
      allow(work_schema_analyzer).to receive(:required_terms).and_return(['title', 'creator'])
      allow(work_schema_analyzer).to receive(:controlled_vocab_terms)
        .and_return(['rights_statement', 'resource_type'])

      # Setup Collection
      allow(Bulkrax::SampleCsvService::ModelLoader).to receive(:determine_klass_for)
        .with('Collection').and_return(collection_klass)
      allow(collection_klass).to receive(:respond_to?).and_return(false)
      allow(collection_klass).to receive(:respond_to?).with(:schema).and_return(false)
      allow(collection_klass).to receive(:properties)
        .and_return({ 'title' => {}, 'description' => {} })
      allow(Bulkrax::SampleCsvService::SchemaAnalyzer).to receive(:new)
        .with(collection_klass).and_return(collection_schema_analyzer)
      allow(collection_schema_analyzer).to receive(:required_terms).and_return(['title'])
      allow(collection_schema_analyzer).to receive(:controlled_vocab_terms)
        .and_return(['visibility', 'rights_statement'])
    end

    it 'builds field list and provides controlled vocab terms for multiple models' do
      # Create entries for both models
      analyzer.find_or_create_field_list_for(model_name: 'Work')
      analyzer.find_or_create_field_list_for(model_name: 'Collection')

      # Verify field list contains both
      expect(analyzer.field_list.size).to eq(2)

      # Verify controlled vocab terms are combined and unique
      expect(analyzer.controlled_vocab_terms).to contain_exactly(
        'rights_statement', 'resource_type', 'visibility'
      )

      # Verify repeated calls return existing entries
      work_result = analyzer.find_or_create_field_list_for(model_name: 'Work')
      expect(work_result['Work']['properties']).to eq(['title', 'creator', 'rights_statement'])
      expect(analyzer.field_list.size).to eq(2) # Still only 2 entries
    end
  end
end
