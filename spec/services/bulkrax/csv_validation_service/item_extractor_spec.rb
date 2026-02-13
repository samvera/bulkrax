# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvValidationService::ItemExtractor do
  let(:csv_data) do
    [
      {
        source_identifier: 'work1',
        model: 'GenericWork',
        parent: nil,
        raw_row: { 'title' => 'Work 1' }
      },
      {
        source_identifier: 'work2',
        model: 'GenericWork',
        parent: 'col1',
        raw_row: { 'title' => 'Work 2' }
      },
      {
        source_identifier: 'col1',
        model: 'Collection',
        parent: nil,
        raw_row: { 'title' => 'Collection 1' }
      },
      {
        source_identifier: 'fs1',
        model: 'FileSet',
        parent: 'work1',
        raw_row: { 'title' => 'File Set 1' }
      }
    ]
  end

  describe '#collections' do
    it 'extracts collection items' do
      extractor = described_class.new(csv_data)
      collections = extractor.collections

      expect(collections.length).to eq(1)
      expect(collections.first[:id]).to eq('col1')
      expect(collections.first[:title]).to eq('Collection 1')
      expect(collections.first[:type]).to eq('collection')
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

    it 'includes parent IDs' do
      extractor = described_class.new(csv_data)
      works = extractor.works
      work_with_parent = works.find { |w| w[:id] == 'work2' }

      expect(work_with_parent[:parentId]).to eq('col1')
    end

    it 'uses source_identifier as title fallback' do
      data_without_title = [
        {
          source_identifier: 'work3',
          model: 'GenericWork',
          parent: nil,
          raw_row: {}
        }
      ]
      extractor = described_class.new(data_without_title)
      works = extractor.works

      expect(works.first[:title]).to eq('work3')
    end
  end

  describe '#file_sets' do
    it 'extracts file set items' do
      extractor = described_class.new(csv_data)
      file_sets = extractor.file_sets

      expect(file_sets.length).to eq(1)
      expect(file_sets.first[:id]).to eq('fs1')
      expect(file_sets.first[:type]).to eq('file_set')
      expect(file_sets.first[:parentId]).to eq('work1')
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
end
