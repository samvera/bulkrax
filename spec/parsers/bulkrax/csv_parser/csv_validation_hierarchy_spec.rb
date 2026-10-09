# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvParser::CsvValidationHierarchy do
  let(:host) { Object.new.tap { |o| o.extend(described_class) } }

  # Builds a minimal record matching the shape produced by parse_validation_rows.
  def make_item(source_identifier:, model: 'GenericWork', parent: nil, children: nil, raw_row: {})
    { source_identifier: source_identifier, model: model,
      parent: parent, children: children, file: nil, raw_row: raw_row }
  end

  # ─── parse_relationship_field ────────────────────────────────────────────────

  describe '#parse_relationship_field' do
    it 'returns an empty array for nil' do
      expect(host.parse_relationship_field(nil)).to eq([])
    end

    it 'returns an empty array for a blank string' do
      expect(host.parse_relationship_field('')).to eq([])
    end

    it 'returns a single-element array for a plain value' do
      expect(host.parse_relationship_field('col1')).to eq(['col1'])
    end

    it 'splits on | by default' do
      expect(host.parse_relationship_field('col1|col2')).to eq(%w[col1 col2])
    end

    it 'strips whitespace from each value' do
      expect(host.parse_relationship_field(' col1 | col2 ')).to eq(%w[col1 col2])
    end
  end

  # ─── build_child_to_parents_map ─────────────────────────────────────────────

  describe '#build_child_to_parents_map' do
    context 'with a single children column' do
      it 'maps each child id to its parent source_identifier' do
        data = [
          make_item(source_identifier: 'col1', model: 'Collection', children: 'work1|work2'),
          make_item(source_identifier: 'work1'),
          make_item(source_identifier: 'work2')
        ]
        map = host.build_child_to_parents_map(data)
        expect(map['work1']).to eq(['col1'])
        expect(map['work2']).to eq(['col1'])
      end

      it 'returns an empty array for items with no parent in the map' do
        data = [make_item(source_identifier: 'work1')]
        map = host.build_child_to_parents_map(data)
        expect(map['work1']).to eq([])
      end
    end

    context 'with children spread across suffix columns (children_1, children_2)' do
      it 'maps children from children_1 and children_2 to the parent' do
        data = [
          make_item(source_identifier: 'col1', model: 'Collection',
                    children: nil,
                    raw_row: { 'children_1' => 'work1', 'children_2' => 'work2' }),
          make_item(source_identifier: 'work1'),
          make_item(source_identifier: 'work2')
        ]
        map = host.build_child_to_parents_map(data)
        expect(map['work1']).to eq(['col1'])
        expect(map['work2']).to eq(['col1'])
      end

      it 'combines base children column and suffix columns when both are present' do
        data = [
          make_item(source_identifier: 'col1', model: 'Collection',
                    children: 'work1',
                    raw_row: { 'children_2' => 'work2' }),
          make_item(source_identifier: 'work1'),
          make_item(source_identifier: 'work2')
        ]
        map = host.build_child_to_parents_map(data)
        expect(map['work1']).to eq(['col1'])
        expect(map['work2']).to eq(['col1'])
      end
    end

    context 'equivalence: single column with delimiter vs suffix columns' do
      it 'produces the same parent map regardless of which form is used' do
        split_data = [
          make_item(source_identifier: 'col1', model: 'Collection', children: 'work1|work2')
        ]
        suffix_data = [
          make_item(source_identifier: 'col1', model: 'Collection',
                    children: nil,
                    raw_row: { 'children_1' => 'work1', 'children_2' => 'work2' })
        ]
        expect(host.build_child_to_parents_map(split_data))
          .to eq(host.build_child_to_parents_map(suffix_data))
      end
    end
  end

  # ─── build_item_hash ─────────────────────────────────────────────────────────

  describe '#build_item_hash' do
    let(:all_ids) { Set.new(%w[col1 work1 work2]) }

    context 'with parent ids in suffix columns (parents_1, parents_2)' do
      it 'includes suffix parent ids in parentIds' do
        item = make_item(source_identifier: 'work1',
                         parent: nil,
                         raw_row: { 'title' => 'Work One', 'parents_1' => 'col1' })
        hash = host.build_item_hash(item, {}, all_ids, type: 'work')
        expect(hash[:parentIds]).to include('col1')
      end

      it 'includes all suffix parent ids when multiple are present' do
        item = make_item(source_identifier: 'work1',
                         parent: nil,
                         raw_row: { 'title' => 'Work One',
                                    'parents_1' => 'col1',
                                    'parents_2' => 'col2' })
        hash = host.build_item_hash(item, {}, Set.new(%w[col1 col2 work1]), type: 'work')
        expect(hash[:parentIds]).to contain_exactly('col1', 'col2')
      end

      it 'combines base parent field and suffix columns when both are present' do
        item = make_item(source_identifier: 'work1',
                         parent: 'col1',
                         raw_row: { 'title' => 'Work One', 'parents_2' => 'col2' })
        hash = host.build_item_hash(item, {}, Set.new(%w[col1 col2 work1]), type: 'work')
        expect(hash[:parentIds]).to contain_exactly('col1', 'col2')
      end
    end

    context 'with child ids in suffix columns (children_1, children_2)' do
      it 'includes suffix child ids in childIds' do
        item = make_item(source_identifier: 'col1', model: 'Collection',
                         children: nil,
                         raw_row: { 'title' => 'Coll', 'children_1' => 'work1' })
        hash = host.build_item_hash(item, {}, all_ids, type: 'collection')
        expect(hash[:childIds]).to include('work1')
      end

      it 'includes all suffix child ids when multiple are present' do
        item = make_item(source_identifier: 'col1', model: 'Collection',
                         children: nil,
                         raw_row: { 'title' => 'Coll',
                                    'children_1' => 'work1',
                                    'children_2' => 'work2' })
        hash = host.build_item_hash(item, {}, all_ids, type: 'collection')
        expect(hash[:childIds]).to contain_exactly('work1', 'work2')
      end

      it 'combines base children field and suffix columns when both are present' do
        item = make_item(source_identifier: 'col1', model: 'Collection',
                         children: 'work1',
                         raw_row: { 'title' => 'Coll', 'children_2' => 'work2' })
        hash = host.build_item_hash(item, {}, all_ids, type: 'collection')
        expect(hash[:childIds]).to contain_exactly('work1', 'work2')
      end
    end

    context 'equivalence: single column with delimiter vs suffix columns' do
      it 'produces identical parentIds regardless of which form is used' do
        split_item = make_item(source_identifier: 'work1',
                               parent: 'col1|col2',
                               raw_row: { 'title' => 'Work' })
        suffix_item = make_item(source_identifier: 'work1',
                                parent: nil,
                                raw_row: { 'title' => 'Work',
                                           'parents_1' => 'col1',
                                           'parents_2' => 'col2' })
        ids = Set.new(%w[col1 col2 work1])
        # Pattern is a regex source; escape '|' so it's not empty-alternation.
        split_hash  = host.build_item_hash(split_item,  {}, ids, type: 'work', parent: '\\|')
        suffix_hash = host.build_item_hash(suffix_item, {}, ids, type: 'work')
        expect(split_hash[:parentIds]).to eq(suffix_hash[:parentIds])
      end

      it 'produces identical childIds regardless of which form is used' do
        split_item = make_item(source_identifier: 'col1', model: 'Collection',
                               children: 'work1|work2',
                               raw_row: { 'title' => 'Coll' })
        suffix_item = make_item(source_identifier: 'col1', model: 'Collection',
                                children: nil,
                                raw_row: { 'title' => 'Coll',
                                           'children_1' => 'work1',
                                           'children_2' => 'work2' })
        ids = Set.new(%w[col1 work1 work2])
        split_hash  = host.build_item_hash(split_item,  {}, ids, type: 'collection')
        suffix_hash = host.build_item_hash(suffix_item, {}, ids, type: 'collection')
        expect(split_hash[:childIds]).to eq(suffix_hash[:childIds])
      end
    end

    context 'with external (repository) parent ids in suffix columns' do
      it 'includes suffix parent ids in existingParentIds when found in repository' do
        find_record = ->(id) { id == 'repo_col' }
        item = make_item(source_identifier: 'work1',
                         parent: nil,
                         raw_row: { 'title' => 'Work', 'parents_1' => 'repo_col' })
        hash = host.build_item_hash(item, {}, Set.new(['work1']), type: 'work', find_record: find_record)
        expect(hash[:existingParentIds]).to include('repo_col')
      end
    end

    context 'existing flag' do
      it 'sets existing to true when find_record returns true for the item' do
        find_record = ->(id) { id == 'work1' }
        item = make_item(source_identifier: 'work1', raw_row: { 'title' => 'Work One' })
        hash = host.build_item_hash(item, {}, all_ids, type: 'work', find_record: find_record)
        expect(hash[:existing]).to be true
      end

      it 'sets existing to false when find_record returns false for the item' do
        find_record = ->(_id) { false }
        item = make_item(source_identifier: 'work1', raw_row: { 'title' => 'Work One' })
        hash = host.build_item_hash(item, {}, all_ids, type: 'work', find_record: find_record)
        expect(hash[:existing]).to be false
      end

      it 'sets existing to false when find_record is nil' do
        item = make_item(source_identifier: 'work1', raw_row: { 'title' => 'Work One' })
        hash = host.build_item_hash(item, {}, all_ids, type: 'work')
        expect(hash[:existing]).to be false
      end
    end
  end

  # ─── custom split patterns ───────────────────────────────────────────────────

  describe 'custom split patterns' do
    let(:all_ids) { Set.new(%w[col1 work1 work2]) }

    context 'build_child_to_parents_map with a custom children split pattern' do
      it 'splits children on the configured pattern' do
        data = [
          make_item(source_identifier: 'col1', model: 'Collection', children: 'work1;work2'),
          make_item(source_identifier: 'work1'),
          make_item(source_identifier: 'work2')
        ]
        map = host.build_child_to_parents_map(data, child_split_pattern: ';')
        expect(map['work1']).to eq(['col1'])
        expect(map['work2']).to eq(['col1'])
      end

      it 'does not split on | when a different pattern is configured' do
        data = [
          make_item(source_identifier: 'col1', model: 'Collection', children: 'work1|work2')
        ]
        map = host.build_child_to_parents_map(data, child_split_pattern: ';')
        expect(map['work1|work2']).to eq(['col1'])
        expect(map['work1']).to eq([])
      end
    end

    context 'build_item_hash with custom split patterns' do
      it 'splits parents on the configured parent split pattern' do
        item = make_item(source_identifier: 'work1',
                         parent: 'col1;col2',
                         raw_row: { 'title' => 'Work' })
        hash = host.build_item_hash(item, {}, Set.new(%w[col1 col2 work1]),
                                    type: 'work', parent: ';')
        expect(hash[:parentIds]).to contain_exactly('col1', 'col2')
      end

      it 'splits children on the configured child split pattern' do
        item = make_item(source_identifier: 'col1', model: 'Collection',
                         children: 'work1;work2',
                         raw_row: { 'title' => 'Coll' })
        hash = host.build_item_hash(item, {}, all_ids,
                                    type: 'collection', child: ';')
        expect(hash[:childIds]).to contain_exactly('work1', 'work2')
      end
    end

    context 'extract_validation_items with custom split patterns' do
      it 'passes split patterns through to item building' do
        data = [
          make_item(source_identifier: 'col1', model: 'Collection',
                    children: 'work1;work2',
                    raw_row: { 'title' => 'Coll' }),
          make_item(source_identifier: 'work1', parent: 'col1', raw_row: { 'title' => 'W1' }),
          make_item(source_identifier: 'work2', parent: 'col1', raw_row: { 'title' => 'W2' })
        ]
        ids = Set.new(%w[col1 work1 work2])
        collections, works, = host.extract_validation_items(
          data, ids, nil,
          parent_split_pattern: nil, child_split_pattern: ';'
        )
        expect(collections.first[:childIds]).to contain_exactly('work1', 'work2')
        expect(works.map { |w| w[:parentIds] }.flatten).to all(include('col1'))
      end
    end
  end

  # ─── extract_validation_items ────────────────────────────────────────────────

  describe '#extract_validation_items' do
    it 'correctly categorises a collection with suffix-column children' do
      data = [
        make_item(source_identifier: 'col1', model: 'Collection',
                  children: nil,
                  raw_row: { 'title' => 'My Collection',
                             'children_1' => 'work1',
                             'children_2' => 'work2' }),
        make_item(source_identifier: 'work1', raw_row: { 'title' => 'Work One' }),
        make_item(source_identifier: 'work2', raw_row: { 'title' => 'Work Two' })
      ]
      all_ids = Set.new(%w[col1 work1 work2])
      collections, works, = host.extract_validation_items(data, all_ids)

      expect(collections.length).to eq(1)
      expect(collections.first[:childIds]).to contain_exactly('work1', 'work2')
      expect(works.map { |w| w[:parentIds] }.flatten).to include('col1')
    end

    it 'correctly categorises a work with suffix-column parents' do
      data = [
        make_item(source_identifier: 'col1', model: 'Collection',
                  raw_row: { 'title' => 'My Collection' }),
        make_item(source_identifier: 'work1',
                  parent: nil,
                  raw_row: { 'title' => 'Work One', 'parents_1' => 'col1' })
      ]
      all_ids = Set.new(%w[col1 work1])
      collections, works, = host.extract_validation_items(data, all_ids)

      expect(works.length).to eq(1)
      expect(works.first[:parentIds]).to include('col1')
      expect(collections.first[:childIds]).to be_empty
    end
  end
end
