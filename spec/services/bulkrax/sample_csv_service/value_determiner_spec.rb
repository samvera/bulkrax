# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::SampleCsvService::ValueDeterminer do
  let(:service) { instance_double(Bulkrax::SampleCsvService) }
  let(:value_determiner) { described_class.new(service) }
  let(:mapping_manager) { instance_double(Bulkrax::SampleCsvService::MappingManager) }

  let(:mappings) do
    {
      "file" => { "from" => ["xlocalfiles"], "split" => "|" },
      "remote_files" => { "from" => ["xrefs"], "split" => "|" }
    }
  end

  before do
    allow(service).to receive(:mapping_manager).and_return(mapping_manager)
    allow(service).to receive(:mappings).and_return(mappings)
    allow(mapping_manager).to receive(:find_by_flag).and_return(nil)
  end

  describe '#determine_value' do
    let(:model_name) { 'GenericWork' }
    let(:field_list) do
      {
        'GenericWork' => {
          'properties' => ['title', 'creator', 'description'],
          'required_terms' => ['title']
        }
      }
    end

    context 'when column maps to a model property' do
      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('title').and_return('title')
      end

      it 'returns Required for required properties' do
        result = value_determiner.determine_value('title', model_name, field_list)

        expect(result).to eq('Required')
      end

      it 'returns Optional for non-required properties' do
        allow(mapping_manager).to receive(:mapped_to_key).with('creator').and_return('creator')

        result = value_determiner.determine_value('creator', model_name, field_list)

        expect(result).to eq('Optional')
      end
    end

    context 'when column is source_identifier' do
      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('source_identifier').and_return('source_identifier')
      end

      it 'returns Required' do
        result = value_determiner.determine_value('source_identifier', model_name, field_list)

        expect(result).to eq('Required')
      end
    end

    context 'when column is model or work_type' do
      let(:mock_klass) { double('GenericWork', to_s: 'GenericWork') }

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('work_type').and_return('model')
        allow(Bulkrax::SampleCsvService::ModelLoader).to receive(:determine_klass_for)
          .with(model_name).and_return(mock_klass)
      end

      it 'returns the model class name' do
        result = value_determiner.determine_value('work_type', model_name, field_list)

        expect(result).to eq('GenericWork')
      end
    end

    context 'when column is not a property or special column' do
      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('unknown_column').and_return('unknown_key')
      end

      it 'returns nil' do
        result = value_determiner.determine_value('unknown_column', model_name, field_list)

        expect(result).to be_nil
      end
    end

    context 'when required_terms is nil' do
      let(:field_list_without_required) do
        {
          'GenericWork' => {
            'properties' => ['title'],
            'required_terms' => nil
          }
        }
      end

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('title').and_return('title')
      end

      it 'returns Unknown for properties' do
        result = value_determiner.determine_value('title', model_name, field_list_without_required)

        expect(result).to eq('Unknown')
      end
    end

    context 'when column is a relationship column' do
      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('children').and_return('children')
        allow(mapping_manager).to receive(:find_by_flag)
          .with("related_children_field_mapping", 'children').and_return('children')
        allow(mapping_manager).to receive(:find_by_flag)
          .with("related_parents_field_mapping", 'parents').and_return('parents')
      end

      it 'returns Optional' do
        result = value_determiner.determine_value('children', model_name, field_list)

        expect(result).to eq('Optional')
      end
    end

    context 'when column is a file column for a collection' do
      let(:collection_model) { 'Collection' }
      let(:collection_field_list) do
        {
          'Collection' => {
            'properties' => ['title'],
            'required_terms' => ['title']
          }
        }
      end

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('xlocalfiles').and_return('file')
        allow(Bulkrax).to receive(:collection_model_class).and_return(Collection)
      end

      it 'returns nil for file columns on collections' do
        result = value_determiner.determine_value('xlocalfiles', collection_model, collection_field_list)

        expect(result).to be_nil
      end
    end
  end
end
