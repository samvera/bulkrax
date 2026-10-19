# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::RelationshipIds do
  describe '.ids' do
    it 'returns an empty array for a blank cell and no matching columns' do
      expect(described_class.ids(nil, {}, ['parents'], '\|')).to eq([])
      expect(described_class.ids('', {}, ['parents'], '\|')).to eq([])
    end

    it 'keeps an unsplit cell whole when no split pattern is given' do
      expect(described_class.ids('a|b', {}, ['parents'], nil)).to eq(['a|b'])
    end

    it 'splits and strips each value' do
      expect(described_class.ids(' a | b ', {}, ['parents'], '\|')).to eq(%w[a b])
    end

    it 'reads every alias column and its numbered forms, without duplicates' do
      raw_row = { 'collection' => '', 'parents' => 'p1', 'parents_1' => 'p2|p3', 'collection_2' => 'p1', 'title' => 'x' }

      expect(described_class.ids('p1', raw_row, %w[collection parents], '\|')).to eq(%w[p1 p2 p3])
    end

    it 'reads a column numbered with a prefix, as import does' do
      expect(described_class.ids(nil, { '1_parents' => 'p9' }, ['parents'], '\|')).to eq(['p9'])
    end

    it 'ignores columns that only share a prefix with an alias' do
      raw_row = { 'parents_extra' => 'nope', 'grandparents' => 'nope' }

      expect(described_class.ids(nil, raw_row, ['parents'], '\|')).to eq([])
    end
  end

  describe '.columns' do
    it 'returns every alias of the flagged mapping plus its key' do
      mappings = { 'parents' => { 'from' => %w[collection parents], 'related_parents_field_mapping' => true } }

      expect(described_class.columns(mappings, 'related_parents_field_mapping', 'parents')).to eq(%w[collection parents])
    end

    it 'reads the aliases of an unflagged default mapping, as import does' do
      mappings = { 'parents' => { 'from' => ['collection'] } }

      expect(described_class.columns(mappings, 'related_parents_field_mapping', 'parents')).to eq(%w[collection parents])
    end

    it 'falls back to the default when no mapping is flagged' do
      expect(described_class.columns({}, 'related_parents_field_mapping', 'parents')).to eq(['parents'])
    end
  end
end
