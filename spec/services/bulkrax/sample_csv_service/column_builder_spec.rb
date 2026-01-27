# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::SampleCsvService::ColumnBuilder do
  let(:service) { instance_double(Bulkrax::SampleCsvService) }
  let(:column_builder) { described_class.new(service) }
  let(:mapping_manager) { instance_double(Bulkrax::SampleCsvService::MappingManager) }
  let(:field_analyzer) { instance_double(Bulkrax::SampleCsvService::FieldAnalyzer) }
  let(:descriptor) { instance_double(Bulkrax::SampleCsvService::ColumnDescriptor) }

  let(:mappings) do
    {
      "file" => { "from" => ["xlocalfiles"], "split" => "|" },
      "remote_files" => { "from" => ["xrefs"], "split" => "|" }
    }
  end

  before do
    allow(Bulkrax::SampleCsvService::ColumnDescriptor).to receive(:new).and_return(descriptor)
    allow(service).to receive(:mapping_manager).and_return(mapping_manager)
    allow(service).to receive(:field_analyzer).and_return(field_analyzer)
    allow(service).to receive(:mappings).and_return(mappings)
    allow(service).to receive(:all_models).and_return([])
  end

  describe '#initialize' do
    it 'creates a ColumnDescriptor' do
      described_class.new(service)

      expect(Bulkrax::SampleCsvService::ColumnDescriptor).to have_received(:new)
    end

    it 'stores the service reference' do
      builder = described_class.new(service)

      expect(builder.instance_variable_get(:@service)).to eq(service)
    end
  end

  describe '#all_columns' do
    let(:required_cols) { ['work_type', 'source_identifier', 'children'] }
    let(:property_cols) { ['abstract', 'contributor', 'title'] }

    before do
      allow(column_builder).to receive(:required_columns).and_return(required_cols)
      allow(column_builder).to receive(:property_columns).and_return(property_cols)
    end

    it 'combines required and property columns' do
      result = column_builder.all_columns

      expect(result).to eq(required_cols + property_cols)
    end

    it 'maintains column order with required columns first' do
      result = column_builder.all_columns

      expect(result[0..2]).to eq(required_cols)
      expect(result[3..5]).to eq(property_cols)
    end
  end

  describe '#required_columns' do
    let(:mapped_core_cols) { ['work_type', 'source_identifier', 'visibility'] }
    let(:relationship_cols) { ['children', 'parents'] }
    let(:file_cols) { ['xlocalfiles', 'xrefs'] }

    before do
      allow(column_builder).to receive(:mapped_core_columns).and_return(mapped_core_cols)
      allow(column_builder).to receive(:relationship_columns).and_return(relationship_cols)
      allow(column_builder).to receive(:file_columns).and_return(file_cols)
    end

    it 'combines mapped core, relationship, and file columns' do
      result = column_builder.required_columns

      expect(result).to eq(mapped_core_cols + relationship_cols + file_cols)
    end

    it 'returns columns in the correct order' do
      result = column_builder.required_columns

      expect(result[0..2]).to eq(mapped_core_cols)
      expect(result[3..4]).to eq(relationship_cols)
      expect(result[5..6]).to eq(file_cols)
    end
  end

  describe 'private methods' do
    describe '#mapped_core_columns' do
      let(:core_cols) { ['model'] }

      before do
        allow(descriptor).to receive(:core_columns).and_return(core_cols)
      end

      context 'when a mapping exists for model' do
        before do
          allow(mapping_manager).to receive(:key_to_mapped_column).with('model').and_return('work_type')
        end

        it 'maps model column through mapping_manager' do
          result = column_builder.send(:mapped_core_columns)

          expect(result).to eq(['work_type'])
        end

        it 'calls key_to_mapped_column for model' do
          column_builder.send(:mapped_core_columns)

          expect(mapping_manager).to have_received(:key_to_mapped_column).with('model')
        end
      end

      context 'when no mapping exists for model' do
        before do
          allow(mapping_manager).to receive(:key_to_mapped_column).with('model').and_return('model')
        end

        it 'returns original column name' do
          result = column_builder.send(:mapped_core_columns)

          expect(result).to eq(['model'])
        end
      end
    end

    describe '#property_columns' do
      let(:model_names) { ['MyWork', 'AnotherWork'] }
      let(:field_list_1) do
        {
          'MyWork' => {
            'properties' => ['title', 'creator', 'description']
          }
        }
      end
      let(:field_list_2) do
        {
          'AnotherWork' => {
            'properties' => ['title', 'extent', 'format']
          }
        }
      end

      before do
        allow(service).to receive(:all_models).and_return(model_names)
        allow(field_analyzer).to receive(:find_or_create_field_list_for)
          .with(model_name: 'MyWork').and_return(field_list_1)
        allow(field_analyzer).to receive(:find_or_create_field_list_for)
          .with(model_name: 'AnotherWork').and_return(field_list_2)

        # Mock the mapping manager to return mapped column names
        allow(mapping_manager).to receive(:key_to_mapped_column) do |key|
          "x#{key}" # Simple mapping for testing
        end

        # Mock required columns to exclude some properties
        allow(column_builder).to receive(:required_columns).and_return(['xtitle'])
      end

      it 'collects properties from all models' do
        result = column_builder.send(:property_columns)

        # Should include all unique mapped properties except those in required_columns
        expect(result).to include('xcreator', 'xdescription', 'xextent', 'xformat')
        expect(result).not_to include('xtitle') # Excluded as it's in required_columns
      end

      it 'removes duplicates and sorts the result' do
        result = column_builder.send(:property_columns)

        expect(result).to eq(result.uniq.sort)
      end

      it 'maps property names through mapping_manager' do
        column_builder.send(:property_columns)

        expect(mapping_manager).to have_received(:key_to_mapped_column).at_least(:once)
      end

      it 'handles empty field lists gracefully' do
        allow(field_analyzer).to receive(:find_or_create_field_list_for).and_return({})

        result = column_builder.send(:property_columns)

        expect(result).to eq([])
      end
    end

    describe '#relationship_columns' do
      before do
        allow(mapping_manager).to receive(:find_by_flag)
          .with("related_children_field_mapping", 'children')
          .and_return('xchildren')
        allow(mapping_manager).to receive(:find_by_flag)
          .with("related_parents_field_mapping", 'parents')
          .and_return('xparents')
      end

      it 'returns children and parents columns from mapping manager' do
        result = column_builder.send(:relationship_columns)

        expect(result).to eq(['xchildren', 'xparents'])
      end

      it 'uses default values when flags are not found' do
        allow(mapping_manager).to receive(:find_by_flag)
          .with("related_children_field_mapping", 'children')
          .and_return('children')
        allow(mapping_manager).to receive(:find_by_flag)
          .with("related_parents_field_mapping", 'parents')
          .and_return('parents')

        result = column_builder.send(:relationship_columns)

        expect(result).to eq(['children', 'parents'])
      end
    end

    describe '#file_columns' do
      before do
        stub_const('Bulkrax::SampleCsvService::ColumnDescriptor::COLUMN_DESCRIPTIONS', {
                     files: [
                       { "file" => "File description" }
                     ]
                   })
      end

      context 'when a mapping exists for file' do
        before do
          allow(mapping_manager).to receive(:key_to_mapped_column).with('file').and_return('xlocalfiles')
        end

        it 'maps file column through mapping_manager' do
          result = column_builder.send(:file_columns)

          expect(result).to eq(['xlocalfiles'])
        end

        it 'calls key_to_mapped_column for file' do
          column_builder.send(:file_columns)

          expect(mapping_manager).to have_received(:key_to_mapped_column).with('file')
        end
      end

      context 'when no mapping exists for file' do
        before do
          allow(mapping_manager).to receive(:key_to_mapped_column).with('file').and_return('file')
        end

        it 'returns original column name' do
          result = column_builder.send(:file_columns)

          expect(result).to eq(['file'])
        end
      end
    end
  end

  describe 'integration' do
    context 'when mappings exist for model and file columns' do
      before do
        # Set up a complete mock scenario
        allow(descriptor).to receive(:core_columns).and_return(['model', 'source_identifier'])
        allow(mapping_manager).to receive(:find_by_flag)
          .with("related_children_field_mapping", 'children').and_return('children')
        allow(mapping_manager).to receive(:find_by_flag)
          .with("related_parents_field_mapping", 'parents').and_return('parents')

        allow(service).to receive(:all_models).and_return(['MyWork'])
        allow(field_analyzer).to receive(:find_or_create_field_list_for)
          .and_return({ 'MyWork' => { 'properties' => ['title', 'creator'] } })

        # Mock key_to_mapped_column to map model and file specifically
        allow(mapping_manager).to receive(:key_to_mapped_column) do |key|
          case key
          when 'model' then 'work_type'
          when 'file' then 'xlocalfiles'
          else "x#{key}"
          end
        end

        stub_const('Bulkrax::SampleCsvService::ColumnDescriptor::COLUMN_DESCRIPTIONS', {
                     files: [
                       { "file" => "File description" }
                     ]
                   })
      end

      it 'maps model column to work_type' do
        result = column_builder.all_columns

        expect(result).to include('work_type')
        expect(result).not_to include('model')
      end

      it 'maps file column to xlocalfiles' do
        result = column_builder.all_columns

        expect(result).to include('xlocalfiles')
        expect(result).not_to include('file')
      end

      it 'calls key_to_mapped_column for model and file' do
        column_builder.all_columns

        expect(mapping_manager).to have_received(:key_to_mapped_column).with('model').at_least(:once)
        expect(mapping_manager).to have_received(:key_to_mapped_column).with('file').at_least(:once)
      end
    end
  end
end
