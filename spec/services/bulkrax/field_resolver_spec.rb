# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::FieldResolver do
  describe '.fields_for_header' do
    let(:mapping) do
      {
        'creator' => { 'from' => %w[author creator] },
        'title' => { 'from' => ['title'] },
        'file' => { 'from' => %w[item file] }
      }
    end

    it 'returns the canonical key when the header matches a `from:` alias' do
      expect(described_class.fields_for_header(mapping, 'author')).to eq(['creator'])
    end

    it 'returns the canonical key when the header matches the mapping key itself' do
      expect(described_class.fields_for_header(mapping, 'title')).to eq(['title'])
    end

    it 'returns the canonical key when the header matches both an alias and the key' do
      expect(described_class.fields_for_header(mapping, 'creator')).to eq(['creator'])
    end

    it 'returns every canonical key an alias feeds when a header is listed under multiple mappings' do
      mapping_with_overlap = {
        'title' => { 'from' => %w[title name] },
        'display_name' => { 'from' => ['name'] }
      }
      expect(described_class.fields_for_header(mapping_with_overlap, 'name'))
        .to contain_exactly('title', 'display_name')
    end

    it 'falls back to `[header]` when no mapping matches' do
      expect(described_class.fields_for_header(mapping, 'publisher')).to eq(['publisher'])
    end

    it 'falls back to `[header]` when mapping is nil' do
      expect(described_class.fields_for_header(nil, 'title')).to eq(['title'])
    end

    it 'falls back to `[header]` when mapping is empty' do
      expect(described_class.fields_for_header({}, 'title')).to eq(['title'])
    end

    it 'handles a scalar `from:` (non-array)' do
      scalar_mapping = { 'creator' => { 'from' => 'author' } }
      expect(described_class.fields_for_header(scalar_mapping, 'author')).to eq(['creator'])
    end

    it 'reads `:from` (symbol) as well as `"from"` (string)' do
      sym_mapping = { 'creator' => { from: %w[author creator] } }
      expect(described_class.fields_for_header(sym_mapping, 'author')).to eq(['creator'])
    end
  end

  describe '.headers_for_field' do
    it 'returns every `from:` alias plus the mapping key itself' do
      mapping = { 'file' => { 'from' => %w[item file] } }
      expect(described_class.headers_for_field(mapping, 'file')).to contain_exactly('item', 'file')
    end

    it 'includes the mapping key even when `from:` omits it' do
      mapping = { 'file' => { 'from' => ['item'] } }
      expect(described_class.headers_for_field(mapping, 'file')).to contain_exactly('item', 'file')
    end

    it 'returns just the canonical key when `from:` is missing' do
      mapping = { 'file' => {} }
      expect(described_class.headers_for_field(mapping, 'file')).to eq(['file'])
    end

    it 'returns just the canonical key when the mapping has no entry for the key' do
      expect(described_class.headers_for_field({}, 'file')).to eq(['file'])
    end

    it 'returns just the canonical key when mapping is nil' do
      expect(described_class.headers_for_field(nil, 'file')).to eq(['file'])
    end

    it 'deduplicates when `from:` already includes the canonical key' do
      mapping = { 'file' => { 'from' => %w[file item file] } }
      expect(described_class.headers_for_field(mapping, 'file')).to eq(%w[file item])
    end

    it 'reads `:from` (symbol) as well as `"from"` (string) for interop with HWIA-backed mappings' do
      mapping = { 'file' => { from: %w[item file] } }
      expect(described_class.headers_for_field(mapping, 'file')).to contain_exactly('item', 'file')
    end
  end

  describe '.present_header_for_flag' do
    let(:mapping) do
      {
        'parents' => { 'from' => %w[collection parents], 'related_parents_field_mapping' => true },
        'source_identifier' => { 'from' => ['source_identifier'], 'source_identifier' => true }
      }
    end

    it 'returns the canonical name when it appears in the CSV headers' do
      result = described_class.present_header_for_flag(mapping, 'related_parents_field_mapping', %w[parents title])
      expect(result).to eq('parents')
    end

    it 'returns the alias when only the alias appears in the CSV headers' do
      result = described_class.present_header_for_flag(mapping, 'related_parents_field_mapping', %w[collection title])
      expect(result).to eq('collection')
    end

    it 'falls back to the first `from:` alias when no candidate matches the headers' do
      result = described_class.present_header_for_flag(mapping, 'related_parents_field_mapping', %w[title])
      expect(result).to eq('collection')
    end

    it 'falls back to the canonical name when `from:` is empty and no header matches' do
      mapping_with_empty_from = { 'source_identifier' => { 'source_identifier' => true } }
      result = described_class.present_header_for_flag(mapping_with_empty_from, 'source_identifier', %w[title])
      expect(result).to eq('source_identifier')
    end

    it 'returns nil when no mapping has the flag' do
      result = described_class.present_header_for_flag(mapping, 'nonexistent_flag', %w[title])
      expect(result).to be_nil
    end

    it 'tolerates a nil mapping' do
      result = described_class.present_header_for_flag(nil, 'related_parents_field_mapping', %w[parents])
      expect(result).to be_nil
    end

    it 'reads symbol-keyed `:from` and symbol-keyed flag values' do
      sym_mapping = { 'parents' => { from: %w[collection parents], related_parents_field_mapping: true } }
      result = described_class.present_header_for_flag(sym_mapping, 'related_parents_field_mapping', %w[collection title])
      expect(result).to eq('collection')
    end
  end
end
