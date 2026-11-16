# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvParser::CsvValidationHierarchy do
  let(:host) { Object.new.tap { |o| o.extend(described_class) } }

  # Builds a minimal record matching the shape produced by parse_validation_rows.
  def make_item(source_identifier:, model: 'GenericWork', parent: nil, children: nil, raw_row: {})
    { source_identifier: source_identifier, model: model,
      parent: parent, children: children, file: nil, raw_row: raw_row }
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
        map = host.build_child_to_parents_map(data, child_split_pattern: '\|')
        expect(map['work1']).to eq(['col1'])
        expect(map['work2']).to eq(['col1'])
      end

      it "leaves out a delete row's children, which the import never relates" do
        data = [make_item(source_identifier: 'col1', model: 'Collection', children: 'work1').merge(deleting: true),
                make_item(source_identifier: 'work1')]
        map = host.build_child_to_parents_map(data, child_split_pattern: '\\|')
        expect(map['work1']).to eq([])
      end

      it 'returns an empty array for items with no parent in the map' do
        data = [make_item(source_identifier: 'work1')]
        map = host.build_child_to_parents_map(data, child_split_pattern: '\|')
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
        map = host.build_child_to_parents_map(data, child_split_pattern: '\|')
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
        map = host.build_child_to_parents_map(data, child_split_pattern: '\|')
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
        expect(host.build_child_to_parents_map(split_data, child_split_pattern: '\\|'))
          .to eq(host.build_child_to_parents_map(suffix_data, child_split_pattern: '\\|'))
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
        split_hash  = host.build_item_hash(split_item,  {}, ids, type: 'collection', child: '\|')
        suffix_hash = host.build_item_hash(suffix_item, {}, ids, type: 'collection', child: '\|')
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
      let(:item) { make_item(source_identifier: 'work1', raw_row: { 'title' => 'Work One' }) }

      def existing_for(match)
        host.build_item_hash(item, {}, all_ids, type: 'work', find_existing_record: ->(_row) { match })[:existing]
      end

      it 'is true when the import would update an existing record' do
        expect(existing_for(field: nil, value: 'work1')).to be true
      end

      it 'is false when the import would create a record' do
        expect(existing_for(nil)).to be false
      end

      it 'is false when the existing record is of another model' do
        expect(existing_for(field: nil, value: 'work1', existing_model: 'Etd', model: 'GenericWork')).to be false
      end

      it 'is false when the lookup itself failed' do
        expect(existing_for(lookup_failed: true)).to be false
      end

      it 'is false when the id names no record' do
        expect(existing_for(field: 'id', value: 'rec-1', missing: true)).to be false
      end

      it "gives a delete row no relationships, which the import never makes" do
        deleting = make_item(source_identifier: 'work1', parent: 'col1', children: 'work2', raw_row: { 'title' => 'Work One' })
        hash = host.build_item_hash(deleting.merge(deleting: true), { 'work1' => ['col2'] }, Set.new(%w[col1 col2 work2]),
                                    type: 'work', find_record: ->(_id) { true })
        expect(hash.values_at(:parentIds, :childIds, :existingParentIds, :existingChildIds)).to all(be_empty)
      end

      it 'drops references to a row this import deletes, by source identifier or id' do
        item = make_item(source_identifier: 'work2', parent: 'col1', children: 'rec-9', raw_row: { 'title' => 'Work Two' })
        find_record = ->(_id) { true }
        hash = host.build_item_hash(item, { 'work2' => ['col1'] }, Set.new(%w[col1 work2]),
                                    type: 'work', find_record: find_record, deleted_ids: Set.new(%w[col1 rec-9]))
        expect(hash.values_at(:parentIds, :childIds, :existingParentIds, :existingChildIds)).to all(be_empty)
      end

      it 'marks a delete row as deleting, not as an existing record to link' do
        found = ->(_row) { { field: nil, value: 'work1' } }
        hash = host.build_item_hash(item.merge(deleting: true), {}, all_ids, type: 'work', find_existing_record: found)
        expect(hash).to include(deleting: true, existing: false)
      end

      it 'is false when no lookup is provided' do
        expect(host.build_item_hash(item, {}, all_ids, type: 'work')[:existing]).to be false
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

    context 'extract_validation_items without split patterns' do
      it 'keeps numbered relationship cells whole, as import does' do
        data = [
          make_item(source_identifier: 'urn:col1', model: 'Collection', raw_row: { 'title' => 'Coll' }),
          make_item(source_identifier: 'urn:work1', raw_row: { 'title' => 'W1', 'parents_1' => 'urn:col1' })
        ]
        _, works, = host.extract_validation_items(data, Set.new(%w[urn:col1 urn:work1]))
        expect(works.first[:parentIds]).to eq(['urn:col1'])
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

    context 'when rows have blank source identifiers' do
      let(:data) do
        [
          make_item(source_identifier: nil, children: 'repo_child_a', raw_row: { 'title' => 'Work A' }),
          make_item(source_identifier: '', children: 'repo_child_b', raw_row: { 'title' => 'Work B' })
        ]
      end
      let(:find_record) { ->(id) { id.to_s.start_with?('repo_child') } }

      it 'gives each row a distinct id named after its CSV row' do
        _, works, = host.extract_validation_items(data, Set.new, find_record)
        expect(works.map { |w| w[:id] }).to eq(%w[row-2 row-3])
      end

      it 'keeps each row\'s existing children on that row' do
        _, works, = host.extract_validation_items(data, Set.new, find_record)
        expect(works.map { |w| w[:existingChildIds] }).to eq([['repo_child_a'], ['repo_child_b']])
      end

      it 'does not take parents from a row that names a child with the same id' do
        rows = data + [make_item(source_identifier: 'col1', model: 'Collection', children: 'row-2')]
        _, works, = host.extract_validation_items(rows, Set.new(%w[col1]), find_record, child_split_pattern: '\|')
        expect(works.first[:parentIds]).to be_empty
      end

      it 'picks a row id that no CSV row uses as its identifier' do
        rows = data + [make_item(source_identifier: 'row-2', raw_row: { 'title' => 'Named row-2' })]
        _, works, = host.extract_validation_items(rows, Set.new(%w[row-2]), find_record)
        expect(works.map { |w| w[:id] }).to contain_exactly('row-2-1', 'row-3', 'row-2')
      end

      it 'picks a row id that no child relationship names, so a row cannot become its own parent' do
        rows = [make_item(source_identifier: nil, children: 'row-2', raw_row: { 'title' => 'Work A' })]
        _, works, = host.extract_validation_items(rows, Set.new, ->(id) { id == 'row-2' })
        expect(works.first[:id]).not_to eq('row-2')
        expect(works.first[:existingChildIds]).to eq(['row-2'])
      end

      it 'picks a row id that no parent relationship names, so a row cannot become its own parent' do
        rows = [make_item(source_identifier: nil, parent: 'row-2', raw_row: { 'title' => 'Work A' })]
        _, works, = host.extract_validation_items(rows, Set.new, ->(id) { id == 'row-2' })
        expect(works.first[:id]).not_to eq('row-2')
        expect(works.first[:existingParentIds]).to eq(['row-2'])
      end

      it 'does not look up the row ids in the repository' do
        looked_up = []
        recording_find_record = lambda do |id|
          looked_up << id
          find_record.call(id)
        end
        _, works, = host.extract_validation_items(data, Set.new, recording_find_record)
        expect(looked_up).not_to include('row-2', 'row-3')
        expect(works.map { |w| w[:existing] }).to eq([false, false])
      end
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

    context 'when the collection model is configured to a host-app class' do
      before do
        allow(Bulkrax.config).to receive(:collection_model_class).and_return(double(to_s: 'DigitalCollection'))
        Bulkrax.collection_model_names = nil
      end

      after { Bulkrax.collection_model_names = nil }

      it 'categorises rows naming that class as collections' do
        data = [
          make_item(source_identifier: 'col1', model: 'DigitalCollection',
                    raw_row: { 'title' => 'My Collection' }),
          make_item(source_identifier: 'work1', raw_row: { 'title' => 'Work One', 'parents_1' => 'col1' }),
          make_item(source_identifier: 'fs1', model: 'FileSet', raw_row: { 'title' => 'File Set One' })
        ]
        all_ids = Set.new(%w[col1 work1 fs1])
        collections, works, file_sets = host.extract_validation_items(data, all_ids)

        expect(collections.map { |c| c[:id] }).to contain_exactly('col1')
        expect(works.map { |w| w[:id] }).to contain_exactly('work1')
        expect(file_sets.map { |f| f[:id] }).to contain_exactly('fs1')
      end
    end

    context 'when the collection model is an ActiveFedora class paired with Wings' do
      before do
        stub_const('CollectionResource', Class.new)
        Bulkrax.collection_model_names = nil
      end

      after { Bulkrax.collection_model_names = nil }

      it 'categorises rows naming either half of the pair as collections' do
        data = [
          make_item(source_identifier: 'col1', model: 'Collection', raw_row: { 'title' => 'One' }),
          make_item(source_identifier: 'col2', model: 'CollectionResource', raw_row: { 'title' => 'Two' })
        ]
        collections, works, = host.extract_validation_items(data, Set.new(%w[col1 col2]))

        expect(collections.map { |c| c[:id] }).to contain_exactly('col1', 'col2')
        expect(works).to be_empty
      end

      it 'does not categorise the twin when the application does not define it' do
        hide_const('CollectionResource')
        Bulkrax.collection_model_names = nil
        data = [make_item(source_identifier: 'col2', model: 'CollectionResource', raw_row: { 'title' => 'Two' })]

        collections, works, = host.extract_validation_items(data, Set.new(%w[col2]))

        expect(collections).to be_empty
        expect(works.map { |w| w[:id] }).to contain_exactly('col2')
      end
    end

    context 'when collection_model_names is extended by the application' do
      before { allow(Bulkrax.config).to receive(:collection_model_names).and_return(%w[Collection LegacyCollection]) }

      it 'categorises rows naming any of them as collections' do
        data = [
          make_item(source_identifier: 'col1', model: 'Collection', raw_row: { 'title' => 'One' }),
          make_item(source_identifier: 'col2', model: 'LegacyCollection', raw_row: { 'title' => 'Two' }),
          make_item(source_identifier: 'work1', raw_row: { 'title' => 'Work One' })
        ]
        collections, works, = host.extract_validation_items(data, Set.new(%w[col1 col2 work1]))

        expect(collections.map { |c| c[:id] }).to contain_exactly('col1', 'col2')
        expect(works.map { |w| w[:id] }).to contain_exactly('work1')
      end
    end
  end
end
