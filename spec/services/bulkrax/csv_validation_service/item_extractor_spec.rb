# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvValidationService::ItemExtractor do
  let(:generic_work_class) { class_double('GenericWork') }
  let(:collection_class) { class_double('Collection') }
  let(:file_set_class) { class_double('FileSet') }

  let(:csv_data) do
    [
      {
        source_identifier: 'work1',
        model: 'GenericWork',
        parent: nil,
        children: nil,
        raw_row: { 'title' => 'Work 1' }
      },
      {
        source_identifier: 'work2',
        model: 'GenericWork',
        parent: 'col1',
        children: nil,
        raw_row: { 'title' => 'Work 2' }
      },
      {
        source_identifier: 'col1',
        model: 'Collection',
        parent: nil,
        children: nil,
        raw_row: { 'title' => 'Collection 1' }
      },
      {
        source_identifier: 'fs1',
        model: 'FileSet',
        parent: 'work1',
        children: nil,
        raw_row: { 'title' => 'File Set 1' }
      }
    ]
  end

  before do
    allow(Bulkrax).to receive(:collection_model_class).and_return(collection_class)
    allow(Bulkrax).to receive(:file_model_class).and_return(file_set_class)

    allow(Bulkrax::CsvValidationService::ModelLoader).to receive(:determine_klass_for) do |model_name|
      case model_name
      when 'GenericWork'
        generic_work_class
      when 'Collection'
        collection_class
      when 'FileSet'
        file_set_class
      end
    end

    allow(generic_work_class).to receive(:name).and_return('GenericWork')
    allow(collection_class).to receive(:name).and_return('Collection')
    allow(file_set_class).to receive(:name).and_return('FileSet')
  end

  describe '#collections' do
    it 'extracts collection items' do
      extractor = described_class.new(csv_data)
      collections = extractor.collections

      expect(collections.length).to eq(1)
      expect(collections.first[:id]).to eq('col1')
      expect(collections.first[:title]).to eq('Collection 1')
      expect(collections.first[:type]).to eq('collection')
      expect(collections.first[:parentIds]).to eq([])
      expect(collections.first[:childIds]).to eq([])
    end

    it 'includes childIds from children column' do
      data_with_children = [
        {
          source_identifier: 'col1',
          model: 'Collection',
          parent: nil,
          children: 'work1|work2',
          raw_row: { 'title' => 'Collection 1' }
        }
      ]
      extractor = described_class.new(data_with_children)
      collections = extractor.collections

      expect(collections.first[:childIds]).to eq(['work1', 'work2'])
    end

    it 'infers parentIds from other items children column' do
      data_with_children = [
        {
          source_identifier: 'col1',
          model: 'Collection',
          parent: nil,
          children: 'col2',
          raw_row: { 'title' => 'Collection 1' }
        },
        {
          source_identifier: 'col2',
          model: 'Collection',
          parent: nil,
          children: nil,
          raw_row: { 'title' => 'Collection 2' }
        }
      ]
      extractor = described_class.new(data_with_children)
      collections = extractor.collections
      child_collection = collections.find { |c| c[:id] == 'col2' }

      expect(child_collection[:parentIds]).to eq(['col1'])
    end

    it 'combines explicit parents with inferred parents from children' do
      data_with_both = [
        {
          source_identifier: 'col1',
          model: 'Collection',
          parent: nil,
          children: 'col3',
          raw_row: { 'title' => 'Collection 1' }
        },
        {
          source_identifier: 'col2',
          model: 'Collection',
          parent: nil,
          children: 'col3',
          raw_row: { 'title' => 'Collection 2' }
        },
        {
          source_identifier: 'col3',
          model: 'Collection',
          parent: 'col1',
          children: nil,
          raw_row: { 'title' => 'Collection 3' }
        }
      ]
      extractor = described_class.new(data_with_both)
      collections = extractor.collections
      child_collection = collections.find { |c| c[:id] == 'col3' }

      # Should have col1 both explicitly (from parent) and inferred (from col1's children)
      # But .uniq should deduplicate, plus col2 from its children
      expect(child_collection[:parentIds]).to contain_exactly('col1', 'col2')
    end

    it 'returns empty array when no collections' do
      data_without_collections = csv_data.reject { |item| item[:model] == 'Collection' }
      extractor = described_class.new(data_without_collections)
      expect(extractor.collections).to be_empty
    end
  end

  describe '#works' do
    it 'extracts work items excluding collections and file sets' do
      extractor = described_class.new(csv_data)
      works = extractor.works

      expect(works.length).to eq(2)
      expect(works.map { |w| w[:id] }).to contain_exactly('work1', 'work2')
      expect(works.first[:type]).to eq('work')
    end

    it 'includes parentIds as array' do
      extractor = described_class.new(csv_data)
      works = extractor.works
      work_with_parent = works.find { |w| w[:id] == 'work2' }

      expect(work_with_parent[:parentIds]).to eq(['col1'])
    end

    it 'includes childIds from children column' do
      data_with_children = [
        {
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: nil,
          children: 'work2|work3',
          raw_row: { 'title' => 'Work 1' }
        },
        {
          source_identifier: 'work2',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: { 'title' => 'Work 2' }
        }
      ]
      extractor = described_class.new(data_with_children)
      works = extractor.works
      parent_work = works.find { |w| w[:id] == 'work1' }

      expect(parent_work[:childIds]).to eq(['work2', 'work3'])
    end

    it 'infers parentIds from other works children column' do
      data_with_children = [
        {
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: nil,
          children: 'work2|work3',
          raw_row: { 'title' => 'Work 1' }
        },
        {
          source_identifier: 'work2',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: { 'title' => 'Work 2' }
        },
        {
          source_identifier: 'work3',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: { 'title' => 'Work 3' }
        }
      ]
      extractor = described_class.new(data_with_children)
      works = extractor.works
      child_work2 = works.find { |w| w[:id] == 'work2' }
      child_work3 = works.find { |w| w[:id] == 'work3' }

      expect(child_work2[:parentIds]).to eq(['work1'])
      expect(child_work3[:parentIds]).to eq(['work1'])
    end

    it 'combines explicit parents with inferred parents from children' do
      data_with_both = [
        {
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: nil,
          children: 'work3',
          raw_row: { 'title' => 'Work 1' }
        },
        {
          source_identifier: 'work2',
          model: 'GenericWork',
          parent: nil,
          children: 'work3',
          raw_row: { 'title' => 'Work 2' }
        },
        {
          source_identifier: 'work3',
          model: 'GenericWork',
          parent: 'work1',
          children: nil,
          raw_row: { 'title' => 'Work 3' }
        }
      ]
      extractor = described_class.new(data_with_both)
      works = extractor.works
      child_work = works.find { |w| w[:id] == 'work3' }

      # Should have work1 explicitly (from parent) and work1 & work2 inferred (from their children)
      # .uniq should deduplicate work1
      expect(child_work[:parentIds]).to contain_exactly('work1', 'work2')
    end

    it 'handles pipe-delimited multiple parents' do
      data_with_multiple_parents = [
        {
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: 'col1|col2',
          children: nil,
          raw_row: { 'title' => 'Work 1' }
        }
      ]
      extractor = described_class.new(data_with_multiple_parents)
      works = extractor.works

      expect(works.first[:parentIds]).to eq(['col1', 'col2'])
    end

    it 'uses source_identifier as title fallback' do
      data_without_title = [
        {
          source_identifier: 'work3',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: {}
        }
      ]
      extractor = described_class.new(data_without_title)
      works = extractor.works

      expect(works.first[:title]).to eq('work3')
      expect(works.first[:parentIds]).to eq([])
      expect(works.first[:childIds]).to eq([])
    end
  end

  describe '#file_sets' do
    it 'extracts file set items without parentIds' do
      extractor = described_class.new(csv_data)
      file_sets = extractor.file_sets

      expect(file_sets.length).to eq(1)
      expect(file_sets.first[:id]).to eq('fs1')
      expect(file_sets.first[:type]).to eq('file_set')
      expect(file_sets.first).not_to have_key(:parentIds)
    end

    it 'returns empty array when no file sets' do
      data_without_file_sets = csv_data.reject { |item| item[:model] == 'FileSet' }
      extractor = described_class.new(data_without_file_sets)
      expect(extractor.file_sets).to be_empty
    end
  end

  describe '#total_count' do
    it 'returns total number of items' do
      extractor = described_class.new(csv_data)
      expect(extractor.total_count).to eq(4)
    end

    it 'returns 0 for empty data' do
      extractor = described_class.new([])
      expect(extractor.total_count).to eq(0)
    end
  end

  describe 'bidirectional parent-child relationship resolution' do
    it 'handles complex multi-level hierarchies' do
      data = [
        {
          source_identifier: 'col1',
          model: 'Collection',
          parent: nil,
          children: 'col2|work1',
          raw_row: { 'title' => 'Top Collection' }
        },
        {
          source_identifier: 'col2',
          model: 'Collection',
          parent: nil,
          children: 'work2|work3',
          raw_row: { 'title' => 'Sub Collection' }
        },
        {
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: { 'title' => 'Work 1' }
        },
        {
          source_identifier: 'work2',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: { 'title' => 'Work 2' }
        },
        {
          source_identifier: 'work3',
          model: 'GenericWork',
          parent: nil,
          children: nil,
          raw_row: { 'title' => 'Work 3' }
        }
      ]
      extractor = described_class.new(data)
      collections = extractor.collections
      works = extractor.works

      # col1 should have col2 and work1 as children
      expect(collections.find { |c| c[:id] == 'col1' }[:childIds]).to eq(['col2', 'work1'])

      # col2 should have col1 as parent and work2, work3 as children
      expect(collections.find { |c| c[:id] == 'col2' }[:parentIds]).to eq(['col1'])
      expect(collections.find { |c| c[:id] == 'col2' }[:childIds]).to eq(['work2', 'work3'])

      # work1 should have col1 as parent
      expect(works.find { |w| w[:id] == 'work1' }[:parentIds]).to eq(['col1'])

      # work2 and work3 should have col2 as parent
      expect(works.find { |w| w[:id] == 'work2' }[:parentIds]).to eq(['col2'])
      expect(works.find { |w| w[:id] == 'work3' }[:parentIds]).to eq(['col2'])
    end

    it 'handles works with multiple parents from different sources' do
      data = [
        {
          source_identifier: 'col1',
          model: 'Collection',
          parent: nil,
          children: 'work1',
          raw_row: { 'title' => 'Collection 1' }
        },
        {
          source_identifier: 'col2',
          model: 'Collection',
          parent: nil,
          children: 'work1',
          raw_row: { 'title' => 'Collection 2' }
        },
        {
          source_identifier: 'work1',
          model: 'GenericWork',
          parent: 'col3',
          children: nil,
          raw_row: { 'title' => 'Work 1' }
        },
        {
          source_identifier: 'col3',
          model: 'Collection',
          parent: nil,
          children: nil,
          raw_row: { 'title' => 'Collection 3' }
        }
      ]
      extractor = described_class.new(data)
      works = extractor.works

      # work1 should have col1 and col2 (from their children) plus col3 (explicit parent)
      expect(works.first[:parentIds]).to contain_exactly('col1', 'col2', 'col3')
    end
  end
end
