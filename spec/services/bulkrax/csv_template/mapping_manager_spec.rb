# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvTemplate::MappingManager do
  let(:manager) { described_class.new }

  before do
    # Stub Bulkrax field mappings
    allow(Bulkrax).to receive(:field_mappings).and_return({
                                                            'Bulkrax::CsvParser' => {
                                                              'title' => { 'from' => ['title'], 'split' => false },
                                                              'model' => { 'from' => ['work_type', 'model'], 'split' => false },
                                                              'file' => { 'from' => ['files', 'items', 'file'], 'split' => false },
                                                              'source_identifier' => { 'from' => ['source_id'], 'source_identifier' => true },
                                                              'parents' => { 'from' => ['parent_ids'], 'related_parents_field_mapping' => true },
                                                              'creator' => { 'from' => ['creator'], 'split' => '|' },
                                                              'generated_field' => { 'from' => ['generated'], 'generated' => true }
                                                            }
                                                          })
  end

  describe '#initialize' do
    it 'loads mappings and filters out generated fields' do
      expect(manager.mappings).to be_a(Hash)
      expect(manager.mappings).to have_key('title')
      expect(manager.mappings).not_to have_key('generated_field')
    end
  end

  describe '#mapped_to_key' do
    it 'finds the key for a given column name' do
      expect(manager.mapped_to_key('work_type')).to eq('model')
    end

    it 'returns the column name if no mapping found' do
      expect(manager.mapped_to_key('unknown_column')).to eq('unknown_column')
    end
  end

  describe '#key_to_mapped_column' do
    it 'returns the mapped column name for a key' do
      expect(manager.key_to_mapped_column('model')).to eq('work_type')
    end

    it 'returns the key if no mapping found' do
      expect(manager.key_to_mapped_column('unmapped_key')).to eq('unmapped_key')
    end
  end

  describe '#find_by_flag' do
    it 'finds a key with the specified flag set to true' do
      expect(manager.find_by_flag('source_identifier', 'default')).to eq('source_identifier')
    end

    it 'returns default if flag not found' do
      expect(manager.find_by_flag('nonexistent_flag', 'default_value')).to eq('default_value')
    end
  end

  describe '#split_value_for' do
    it 'returns the split character for a mapping key' do
      expect(manager.split_value_for('creator')).to eq('|')
    end

    it 'returns nil if split not configured' do
      expect(manager.split_value_for('title')).to be false
    end
  end

  describe '#resolve_column_name' do
    context 'with direct key lookup' do
      it 'returns all mapped columns by key' do
        result = manager.resolve_column_name(key: 'model', default: 'model')
        expect(result).to eq(['work_type', 'model'])
      end

      it 'returns default as array if no custom mapping exists' do
        result = manager.resolve_column_name(key: 'unmapped', default: 'unmapped')
        expect(result).to eq(['unmapped'])
      end

      it 'returns all options in from array' do
        allow(Bulkrax).to receive(:field_mappings).and_return({
                                                                'Bulkrax::CsvParser' => {
                                                                  'model' => { 'from' => %w[work_type object_type type], 'split' => false }
                                                                }
                                                              })
        new_manager = described_class.new

        result = new_manager.resolve_column_name(key: 'model', default: 'model')
        expect(result).to eq(%w[work_type object_type type])
      end

      it 'returns file options' do
        result = manager.resolve_column_name(key: 'file', default: 'file')
        expect(result).to eq(['files', 'items', 'file'])
      end
    end

    context 'with flag-based lookup' do
      it 'returns all columns by flag' do
        result = manager.resolve_column_name(
          flag: 'source_identifier',
          default: 'source_identifier'
        )
        expect(result).to eq(['source_id'])
      end

      it 'returns all parent columns by flag' do
        result = manager.resolve_column_name(
          flag: 'related_parents_field_mapping',
          default: 'parents'
        )
        expect(result).to eq(['parent_ids'])
      end

      it 'returns all options in from array for flagged field' do
        allow(Bulkrax).to receive(:field_mappings).and_return({
                                                                'Bulkrax::CsvParser' => {
                                                                  'source_identifier' => { 'from' => %w[id source_id identifier], 'source_identifier' => true }
                                                                }
                                                              })
        new_manager = described_class.new

        result = new_manager.resolve_column_name(flag: 'source_identifier', default: 'source_identifier')
        expect(result).to eq(%w[id source_id identifier])
      end
    end

    context 'with combined strategies' do
      it 'prioritizes flag over key' do
        result = manager.resolve_column_name(
          key: 'model',
          flag: 'source_identifier',
          default: 'source_identifier'
        )
        expect(result).to eq(['source_id'])
      end

      it 'falls back to key if flag not found' do
        result = manager.resolve_column_name(
          key: 'file',
          flag: 'nonexistent_flag',
          default: 'file'
        )
        expect(result).to eq(['files', 'items', 'file'])
      end

      it 'returns default as array if all strategies fail' do
        result = manager.resolve_column_name(
          key: 'unmapped',
          flag: 'nonexistent_flag',
          default: 'my_default'
        )
        expect(result).to eq(['my_default'])
      end
    end
  end
end
