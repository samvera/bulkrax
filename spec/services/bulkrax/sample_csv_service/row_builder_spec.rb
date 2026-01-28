# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::SampleCsvService::RowBuilder do
  let(:service) { instance_double(Bulkrax::SampleCsvService) }
  let(:row_builder) { described_class.new(service) }
  let(:explanation_builder) { instance_double(Bulkrax::SampleCsvService::ExplanationBuilder) }
  let(:value_determiner) { instance_double(Bulkrax::SampleCsvService::ValueDeterminer) }
  let(:field_analyzer) { instance_double(Bulkrax::SampleCsvService::FieldAnalyzer) }

  before do
    allow(Bulkrax::SampleCsvService::ExplanationBuilder).to receive(:new).and_return(explanation_builder)
    allow(Bulkrax::SampleCsvService::ValueDeterminer).to receive(:new).and_return(value_determiner)
    allow(service).to receive(:field_analyzer).and_return(field_analyzer)
  end

  describe '#build_explanation_row' do
    let(:header_row) { ['work_type', 'title', 'creator'] }
    let(:explanations) do
      [
        { 'work_type' => 'Model type', 'split' => '' },
        { 'title' => 'Title of work', 'split' => 'Split with |' },
        { 'creator' => 'Creator name', 'split' => 'Split with |' }
      ]
    end

    before do
      allow(explanation_builder).to receive(:build_explanations).with(header_row).and_return(explanations)
    end

    it 'returns explanations joined as strings' do
      result = row_builder.build_explanation_row(header_row)

      expect(result).to eq(['Model type ', 'Title of work Split with |', 'Creator name Split with |'])
    end
  end

  describe '#build_model_rows' do
    let(:header_row) { ['work_type', 'title', 'creator'] }
    let(:mock_klass) { double('GenericWork') }
    let(:field_list) do
      {
        'GenericWork' => {
          'properties' => ['title', 'creator'],
          'required_terms' => ['title']
        }
      }
    end

    before do
      allow(service).to receive(:all_models).and_return(['GenericWork'])
      allow(Bulkrax::SampleCsvService::ModelLoader).to receive(:determine_klass_for)
        .with('GenericWork').and_return(mock_klass)
      allow(field_analyzer).to receive(:find_or_create_field_list_for)
        .with(model_name: 'GenericWork').and_return(field_list)
      allow(value_determiner).to receive(:determine_value)
        .with('work_type', 'GenericWork', field_list).and_return('GenericWork')
      allow(value_determiner).to receive(:determine_value)
        .with('title', 'GenericWork', field_list).and_return('Required')
      allow(value_determiner).to receive(:determine_value)
        .with('creator', 'GenericWork', field_list).and_return('Optional')
    end

    it 'returns an array of model rows' do
      result = row_builder.build_model_rows(header_row)

      expect(result).to eq([['GenericWork', 'Required', 'Optional']])
    end

    context 'with multiple models' do
      let(:another_mock_klass) { double('Image') }
      let(:another_field_list) do
        {
          'Image' => {
            'properties' => ['title'],
            'required_terms' => ['title']
          }
        }
      end

      before do
        allow(service).to receive(:all_models).and_return(['GenericWork', 'Image'])
        allow(Bulkrax::SampleCsvService::ModelLoader).to receive(:determine_klass_for)
          .with('Image').and_return(another_mock_klass)
        allow(field_analyzer).to receive(:find_or_create_field_list_for)
          .with(model_name: 'Image').and_return(another_field_list)
        allow(value_determiner).to receive(:determine_value)
          .with('work_type', 'Image', another_field_list).and_return('Image')
        allow(value_determiner).to receive(:determine_value)
          .with('title', 'Image', another_field_list).and_return('Required')
        allow(value_determiner).to receive(:determine_value)
          .with('creator', 'Image', another_field_list).and_return(nil)
      end

      it 'returns rows for each model' do
        result = row_builder.build_model_rows(header_row)

        expect(result.length).to eq(2)
        expect(result[0]).to eq(['GenericWork', 'Required', 'Optional'])
        expect(result[1]).to eq(['Image', 'Required', nil])
      end
    end

    context 'when model class cannot be determined' do
      before do
        allow(Bulkrax::SampleCsvService::ModelLoader).to receive(:determine_klass_for)
          .with('GenericWork').and_return(nil)
      end

      it 'returns an empty array for that model' do
        result = row_builder.build_model_rows(header_row)

        expect(result).to eq([[]])
      end
    end
  end
end
