# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvValidationService::ColumnResolver do
  let(:default_mapping_manager) do
    allow(Bulkrax).to receive(:field_mappings).and_return({
                                                            'Bulkrax::CsvParser' => {
                                                              'title' => { 'from' => ['title'], 'split' => false },
                                                              'model' => { 'from' => ['model'], 'split' => false },
                                                              'file' => { 'from' => ['file'], 'split' => false },
                                                              'source_identifier' => { 'from' => ['source_identifier'], 'source_identifier' => true },
                                                              'parents' => { 'from' => ['parents'], 'related_parents_field_mapping' => true }
                                                            }
                                                          })
    Bulkrax::CsvValidationService::MappingManager.new
  end

  let(:custom_mapping_manager) do
    allow(Bulkrax).to receive(:field_mappings).and_return({
                                                            'Bulkrax::CsvParser' => {
                                                              'title' => { 'from' => ['title'], 'split' => false },
                                                              'model' => { 'from' => ['work_type'], 'split' => false },
                                                              'file' => { 'from' => ['files'], 'split' => false },
                                                              'source_identifier' => { 'from' => ['id'], 'source_identifier' => true },
                                                              'parents' => { 'from' => ['parent_collection'], 'related_parents_field_mapping' => true }
                                                            }
                                                          })
    Bulkrax::CsvValidationService::MappingManager.new
  end

  describe '#model_column_name' do
    it 'returns default column name when no custom mapping' do
      resolver = described_class.new(default_mapping_manager)
      expect(resolver.model_column_name).to eq('model')
    end

    it 'returns custom column name from mappings' do
      resolver = described_class.new(custom_mapping_manager)
      expect(resolver.model_column_name).to eq('work_type')
    end
  end

  describe '#source_identifier_column_name' do
    it 'returns column with source_identifier flag' do
      resolver = described_class.new(default_mapping_manager)
      expect(resolver.source_identifier_column_name).to eq('source_identifier')
    end

    it 'returns custom column name from mappings' do
      resolver = described_class.new(custom_mapping_manager)
      expect(resolver.source_identifier_column_name).to eq('id')
    end

    it 'defaults to source_identifier when flag not found' do
      allow(Bulkrax).to receive(:field_mappings).and_return({
                                                              'Bulkrax::CsvParser' => {
                                                                'title' => { 'from' => ['title'] }
                                                              }
                                                            })
      mapping_manager = Bulkrax::CsvValidationService::MappingManager.new
      resolver = described_class.new(mapping_manager)
      csv_headers = ['identifier', 'title']

      expect(resolver.source_identifier_column_name(csv_headers)).to eq('source_identifier')
    end

    it 'defaults to source_identifier when nothing found' do
      allow(Bulkrax).to receive(:field_mappings).and_return({ 'Bulkrax::CsvParser' => {} })
      mapping_manager = Bulkrax::CsvValidationService::MappingManager.new
      resolver = described_class.new(mapping_manager)
      expect(resolver.source_identifier_column_name([])).to eq('source_identifier')
    end
  end

  describe '#parent_column_name' do
    it 'returns column with related_parents_field_mapping flag' do
      resolver = described_class.new(default_mapping_manager)
      expect(resolver.parent_column_name).to eq('parents')
    end

    it 'returns custom column name from mappings' do
      resolver = described_class.new(custom_mapping_manager)
      expect(resolver.parent_column_name).to eq('parent_collection')
    end

    it 'defaults to parents when flag not found' do
      allow(Bulkrax).to receive(:field_mappings).and_return({
                                                              'Bulkrax::CsvParser' => {
                                                                'title' => { 'from' => ['title'] }
                                                              }
                                                            })
      mapping_manager = Bulkrax::CsvValidationService::MappingManager.new
      resolver = described_class.new(mapping_manager)
      csv_headers = ['parent', 'title']

      expect(resolver.parent_column_name(csv_headers)).to eq('parents')
    end

    it 'defaults to parents when nothing found' do
      allow(Bulkrax).to receive(:field_mappings).and_return({ 'Bulkrax::CsvParser' => {} })
      mapping_manager = Bulkrax::CsvValidationService::MappingManager.new
      resolver = described_class.new(mapping_manager)
      expect(resolver.parent_column_name([])).to eq('parents')
    end
  end

  describe '#file_column_name' do
    it 'returns default column name when no custom mapping' do
      resolver = described_class.new(default_mapping_manager)
      expect(resolver.file_column_name).to eq('file')
    end

    it 'returns custom column name from mappings' do
      resolver = described_class.new(custom_mapping_manager)
      expect(resolver.file_column_name).to eq('files')
    end

    it 'defaults to file when key not found' do
      allow(Bulkrax).to receive(:field_mappings).and_return({
                                                              'Bulkrax::CsvParser' => {
                                                                'title' => { 'from' => ['title'] }
                                                              }
                                                            })
      mapping_manager = Bulkrax::CsvValidationService::MappingManager.new
      resolver = described_class.new(mapping_manager)
      csv_headers = ['remote_files', 'title']

      expect(resolver.file_column_name(csv_headers)).to eq('file')
    end

    it 'defaults to file when nothing found' do
      allow(Bulkrax).to receive(:field_mappings).and_return({ 'Bulkrax::CsvParser' => {} })
      mapping_manager = Bulkrax::CsvValidationService::MappingManager.new
      resolver = described_class.new(mapping_manager)
      expect(resolver.file_column_name([])).to eq('file')
    end
  end
end
