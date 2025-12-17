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
    let(:core_cols) { ['work_type', 'source_identifier', 'visibility'] }
    let(:relationship_cols) { ['children', 'parents'] }
    let(:file_cols) { ['xlocalfiles', 'xrefs'] }

    before do
      allow(descriptor).to receive(:core_columns).and_return(core_cols)
      allow(column_builder).to receive(:relationship_columns).and_return(relationship_cols)
      allow(column_builder).to receive(:file_columns).and_return(file_cols)
    end

    it 'combines core, relationship, and file columns' do
      result = column_builder.required_columns

      expect(result).to eq(core_cols + relationship_cols + file_cols)
    end

    it 'returns columns in the correct order' do
      result = column_builder.required_columns

      expect(result[0..2]).to eq(core_cols)
      expect(result[3..4]).to eq(relationship_cols)
      expect(result[5..6]).to eq(file_cols)
    end
  end

  describe 'private methods' do
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
      context 'with file mappings in service.mappings' do
        let(:mappings) do
          {
            "file" => { "from" => ["xlocalfiles"], "split" => "|" },
            "remote_files" => { "from" => ["xremotefiles"], "split" => "|" }
          }
        end

        before do
          allow(service).to receive(:mappings).and_return(mappings)
          # Stub the constant since it's used directly
          stub_const('Bulkrax::SampleCsvService::ColumnDescriptor::COLUMN_DESCRIPTIONS', {
            files: [
              { "file" => "File description" },
              { "remote_files" => "Remote files description" }
            ]
          })
        end

        it 'extracts file columns from mappings' do
          result = column_builder.send(:file_columns)

          expect(result).to eq(['xlocalfiles', 'xremotefiles'])
        end
      end

      context 'with missing mappings' do
        let(:mappings) do
          {
            "file" => { "from" => ["xlocalfiles"] }
            # remote_files mapping is missing
          }
        end

        before do
          allow(service).to receive(:mappings).and_return(mappings)
          stub_const('Bulkrax::SampleCsvService::ColumnDescriptor::COLUMN_DESCRIPTIONS', {
            files: [
              { "file" => "File description" },
              { "remote_files" => "Remote files description" }
            ]
          })
        end

        it 'only returns columns that have mappings' do
          result = column_builder.send(:file_columns)

          expect(result).to eq(['xlocalfiles'])
        end
      end

      context 'with no file mappings' do
        let(:mappings) { {} }

        before do
          allow(service).to receive(:mappings).and_return(mappings)
          stub_const('Bulkrax::SampleCsvService::ColumnDescriptor::COLUMN_DESCRIPTIONS', {
            files: [
              { "file" => "File description" },
              { "remote_files" => "Remote files description" }
            ]
          })
        end

        it 'returns empty array when no mappings exist' do
          result = column_builder.send(:file_columns)

          expect(result).to eq([])
        end
      end
    end
  end

  describe 'integration' do
    before do
      # Set up a complete mock scenario
      allow(descriptor).to receive(:core_columns).and_return(['work_type', 'source_identifier'])
      allow(mapping_manager).to receive(:find_by_flag)
        .with("related_children_field_mapping", 'children').and_return('children')
      allow(mapping_manager).to receive(:find_by_flag)
        .with("related_parents_field_mapping", 'parents').and_return('parents')

      allow(service).to receive(:all_models).and_return(['MyWork'])
      allow(field_analyzer).to receive(:find_or_create_field_list_for)
        .and_return({ 'MyWork' => { 'properties' => ['title', 'creator'] } })
      allow(mapping_manager).to receive(:key_to_mapped_column) do |key|
        "x#{key}"
      end

      stub_const('Bulkrax::SampleCsvService::ColumnDescriptor::COLUMN_DESCRIPTIONS', {
        files: [
          { "file" => "File description" },
          { "remote_files" => "Remote files description" }
        ]
      })
    end

    it 'builds complete column list with no duplicates' do
      result = column_builder.all_columns

      # Should have core, relationship, file, and property columns
      expect(result).to include('work_type', 'source_identifier')  # core
      expect(result).to include('children', 'parents')  # relationships
      expect(result).to include('xlocalfiles', 'xrefs')  # files
      expect(result).to include('xcreator', 'xtitle')  # properties

      # Should have no duplicates
      expect(result).to eq(result.uniq)
    end

    it 'maintains proper column ordering' do
      result = column_builder.all_columns

      # Required columns should come first
      core_idx = result.index('work_type')
      property_idx = result.index('xcreator')

      expect(core_idx).to be < property_idx if property_idx && core_idx
    end
  end
end
