# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvParser::CsvValidationHelpers do
  # Minimal host object that mixes in the concern under test.
  let(:host) do
    Object.new.tap { |o| o.extend(described_class) }
  end

  # All specs in this file exercise the Valkyrie path. ActiveFedora / Wings is
  # not verified to work with this feature, so we configure the factory
  # globally for the file rather than repeating it in every context.
  before { Bulkrax.object_factory = Bulkrax::ValkyrieObjectFactory }
  after  { Bulkrax.object_factory = Bulkrax::ObjectFactory }

  describe '#find_record_by_source_identifier' do
    let(:work_identifier)        { 'source' }
    let(:work_identifier_search) { 'source_sim' }

    def find(id)
      host.find_record_by_source_identifier(id, work_identifier, work_identifier_search)
    end

    context 'when the identifier is blank' do
      it 'returns false for nil' do
        expect(find(nil)).to be false
      end

      it 'returns false for an empty string' do
        expect(find('')).to be false
      end
    end

    context 'when a matching Bulkrax::Entry exists in the database but no repository object does' do
      let!(:importer) { FactoryBot.create(:bulkrax_importer) }
      let!(:entry)    { FactoryBot.create(:bulkrax_csv_entry, identifier: 'entry_id_001', importerexporter: importer) }

      before do
        allow(Hyrax.query_service).to receive(:find_by).and_raise(Hyrax::ObjectNotFoundError)
        allow(Bulkrax).to receive(:collection_model_class).and_return(Collection)
        allow(Bulkrax).to receive(:curation_concerns).and_return([Work])
        allow(Bulkrax::ValkyrieObjectFactory).to receive(:search_by_property).and_return(nil)
      end

      it 'returns false — a Bulkrax Entry alone does not confirm the object exists in the repo' do
        expect(find('entry_id_001')).to be false
      end
    end

    context 'when no Entry exists but the repository has a matching object by ID' do
      # ValkyrieObjectFactory.find_or_nil calls ValkyrieObjectFactory.find which
      # calls Hyrax.query_service.find_by(id:). Stub at that level so we verify
      # the full Valkyrie call chain.
      before do
        allow(Hyrax.query_service).to receive(:find_by)
          .with(id: 'repo-uuid-001')
          .and_return(instance_double(Hyrax::Work))
      end

      it 'returns true' do
        expect(find('repo-uuid-001')).to be true
      end

      it 'does not fall through to search_by_property' do
        expect(Bulkrax::ValkyrieObjectFactory).not_to receive(:search_by_property)
        find('repo-uuid-001')
      end
    end

    context 'when no Entry exists and find_or_nil returns nil' do
      # ValkyrieObjectFactory.find raises ObjectNotFoundError when the object
      # does not exist; find_or_nil rescues that to nil.
      before do
        allow(Hyrax.query_service).to receive(:find_by)
          .and_raise(Hyrax::ObjectNotFoundError)
      end

      context 'when search_by_property finds a match on one of the model classes' do
        before do
          allow(Bulkrax).to receive(:collection_model_class).and_return(Collection)
          allow(Bulkrax).to receive(:curation_concerns).and_return([Work])

          # Collection misses, Work hits.
          allow(Bulkrax::ValkyrieObjectFactory).to receive(:search_by_property)
            .with(value: 'custom_source_001', klass: Collection,
                  search_field: work_identifier_search, name_field: work_identifier)
            .and_return(nil)
          allow(Bulkrax::ValkyrieObjectFactory).to receive(:search_by_property)
            .with(value: 'custom_source_001', klass: Work,
                  search_field: work_identifier_search, name_field: work_identifier)
            .and_return(instance_double(Hyrax::Work))
        end

        it 'returns true' do
          expect(find('custom_source_001')).to be true
        end
      end

      context 'when search_by_property finds nothing across all model classes' do
        before do
          allow(Bulkrax).to receive(:collection_model_class).and_return(Collection)
          allow(Bulkrax).to receive(:curation_concerns).and_return([Work])
          allow(Bulkrax::ValkyrieObjectFactory).to receive(:search_by_property).and_return(nil)
        end

        it 'returns false' do
          expect(find('nonexistent_id')).to be false
        end
      end

      context 'when search_by_property is called with the correct field arguments' do
        let(:work_identifier)        { 'local_id' }
        let(:work_identifier_search) { 'local_id_sim' }

        before do
          allow(Bulkrax).to receive(:collection_model_class).and_return(Collection)
          allow(Bulkrax).to receive(:curation_concerns).and_return([])
          allow(Bulkrax::ValkyrieObjectFactory).to receive(:search_by_property).and_return(nil)
        end

        it 'passes the resolved work_identifier and search field through to search_by_property' do
          expect(Bulkrax::ValkyrieObjectFactory).to receive(:search_by_property).with(
            value: 'some_local_id',
            klass: Collection,
            search_field: 'local_id_sim',
            name_field: 'local_id'
          )
          find('some_local_id')
        end
      end
    end

    context 'when an exception is raised during lookup' do
      before do
        allow(Bulkrax).to receive(:collection_model_class).and_return(Collection)
        allow(Bulkrax).to receive(:curation_concerns).and_return([Work])
        # Simulate an unexpected error in search_by_property that bypasses find_or_nil's rescue
        allow(Bulkrax::ValkyrieObjectFactory).to receive(:search_by_property).and_raise(StandardError, 'Solr unavailable')
        allow(Hyrax.query_service).to receive(:find_by).and_raise(Hyrax::ObjectNotFoundError)
      end

      it 'returns false instead of propagating the error' do
        expect(find('some_id')).to be false
      end
    end
  end

  describe '#build_valid_validation_headers' do
    let(:mapping_manager) { instance_double(Bulkrax::CsvTemplate::MappingManager) }
    let(:field_analyzer)  { instance_double(Bulkrax::CsvTemplate::FieldAnalyzer) }
    let(:field_metadata)  { { 'GenericWork' => { properties: %w[title creator] } } }
    let(:mappings)        { {} }

    context 'when ColumnBuilder raises' do
      before do
        allow(Bulkrax::CsvTemplate::ColumnBuilder).to receive(:new).and_raise(StandardError, 'boom')
      end

      it 'falls back to a standard header list that includes both parents and children' do
        result = host.build_valid_validation_headers(mapping_manager, field_analyzer, [], mappings, field_metadata)
        expect(result).to include('parents', 'children')
      end

      it 'does not include the legacy singular parent column in the fallback' do
        result = host.build_valid_validation_headers(mapping_manager, field_analyzer, [], mappings, field_metadata)
        expect(result).not_to include('parent')
      end

      it 'includes model fields from field_metadata in the fallback' do
        result = host.build_valid_validation_headers(mapping_manager, field_analyzer, [], mappings, field_metadata)
        expect(result).to include('title', 'creator')
      end
    end
  end

  describe '#resolve_children_split_pattern' do
    it 'returns nil when no split is configured for children' do
      mappings = {}
      expect(host.resolve_children_split_pattern(mappings)).to be_nil
    end

    it 'returns nil when children mapping has no split key' do
      mappings = { 'children' => { 'from' => ['children'] } }
      expect(host.resolve_children_split_pattern(mappings)).to be_nil
    end

    it 'returns DEFAULT_MULTI_VALUE_ELEMENT_SPLIT_ON when split is true' do
      mappings = { 'children' => { 'split' => true } }
      expect(host.resolve_children_split_pattern(mappings))
        .to eq(Bulkrax::DEFAULT_MULTI_VALUE_ELEMENT_SPLIT_ON)
    end

    it 'returns the custom split string when split is a string' do
      mappings = { 'children' => { 'split' => ';' } }
      expect(host.resolve_children_split_pattern(mappings)).to eq(';')
    end
  end

  describe '#build_relationship_graph' do
    let(:mappings) { {} }

    def record(source_identifier, parent: nil, children: nil, raw_row: {})
      { source_identifier: source_identifier, parent: parent, children: children, raw_row: raw_row }
    end

    def graph(csv_data)
      host.build_relationship_graph(csv_data, mappings)
    end

    context 'with only parent declarations' do
      it 'maps each record to its declared parents' do
        data = [record('child', parent: 'parent1'), record('parent1')]
        expect(graph(data)).to include('child' => ['parent1'], 'parent1' => [])
      end
    end

    context 'with suffixed parent columns (parents_1, parents_2)' do
      it 'includes all suffixed parent values' do
        data = [
          record('child', raw_row: { 'parents_1' => 'p1', 'parents_2' => 'p2' }),
          record('p1'),
          record('p2')
        ]
        result = graph(data)
        expect(result['child']).to contain_exactly('p1', 'p2')
      end
    end

    context 'with only children declarations' do
      it 'inverts children into parent edges on the child records' do
        data = [record('parent1', children: 'child1'), record('child1')]
        result = graph(data)
        expect(result['child1']).to include('parent1')
      end
    end

    context 'with suffixed children columns (children_1, children_2)' do
      it 'inverts all suffixed children into parent edges' do
        data = [
          record('parent1', raw_row: { 'children_1' => 'c1', 'children_2' => 'c2' }),
          record('c1'),
          record('c2')
        ]
        result = graph(data)
        expect(result['c1']).to include('parent1')
        expect(result['c2']).to include('parent1')
      end
    end

    context 'with a cycle declared via children columns (matching rel-circular-ref.csv pattern)' do
      # child1 declares children=child2; child2 declares children=child1
      # After inversion: child1 → [child2] and child2 → [child1]
      it 'builds a graph that allows cycle detection to flag both nodes' do
        data = [
          record('parent1'),
          record('parent2'),
          record('child1', children: 'child2', raw_row: { 'parents_1' => 'parent1', 'parents_2' => 'parent2' }),
          record('child2', children: 'child1')
        ]
        result = graph(data)
        expect(result['child1']).to include('child2')
        expect(result['child2']).to include('child1')
      end
    end

    context 'when a child is already declared as a parent of the same record' do
      it 'does not add duplicate edges' do
        data = [
          record('a', parent: 'b'),
          record('b', children: 'a')
        ]
        result = graph(data)
        expect(result['a'].count('b')).to eq(1)
      end
    end

    context 'with blank source_identifier' do
      it 'skips the record' do
        data = [record(nil, parent: 'p1'), record('p1')]
        result = graph(data)
        expect(result.keys).not_to include(nil)
      end
    end
  end

  describe '#build_find_record' do
    before do
      allow(Hyrax.query_service).to receive(:find_by).and_raise(Hyrax::ObjectNotFoundError)
      allow(Bulkrax).to receive(:collection_model_class).and_return(Collection)
      allow(Bulkrax).to receive(:curation_concerns).and_return([Work])
      allow(Bulkrax::ValkyrieObjectFactory).to receive(:search_by_property).and_return(nil)
    end

    context 'when no source_identifier entry exists in the raw mappings' do
      before do
        allow(Bulkrax).to receive(:field_mappings).and_return({ 'Bulkrax::CsvParser' => {} })
      end

      it 'returns a callable lambda' do
        expect(host.build_find_record).to respond_to(:call)
      end

      it 'falls back to "source" with "source_sim" search field' do
        lam = host.build_find_record
        expect(Bulkrax::ValkyrieObjectFactory).to receive(:search_by_property).with(
          hash_including(search_field: 'source_sim', name_field: 'source')
        ).and_return(nil)
        lam.call('anything')
      end
    end

    context 'when a non-generated source_identifier mapping exists' do
      before do
        allow(Bulkrax).to receive(:field_mappings).and_return({
                                                                'Bulkrax::CsvParser' => {
                                                                  'local_id' => { 'from' => ['source_identifier'], 'source_identifier' => true, 'search_field' => 'local_id_tesim' }
                                                                }
                                                              })
      end

      it 'uses the mapped search_field' do
        lam = host.build_find_record
        expect(Bulkrax::ValkyrieObjectFactory).to receive(:search_by_property).with(
          hash_including(search_field: 'local_id_tesim', name_field: 'local_id')
        ).and_return(nil)
        lam.call('anything')
      end
    end

    context 'when the source_identifier mapping is a generated entry (e.g. bulkrax_identifier)' do
      before do
        allow(Bulkrax).to receive(:field_mappings).and_return({
                                                                'Bulkrax::CsvParser' => {
                                                                  'bulkrax_identifier' => {
                                                                    'from' => ['source_identifier'], 'source_identifier' => true,
                                                                    'generated' => true, 'search_field' => 'bulkrax_identifier_tesim'
                                                                  }
                                                                }
                                                              })
      end

      it 'resolves the identifier and search_field despite generated:true' do
        lam = host.build_find_record
        expect(Bulkrax::ValkyrieObjectFactory).to receive(:search_by_property).with(
          hash_including(search_field: 'bulkrax_identifier_tesim', name_field: 'bulkrax_identifier')
        ).and_return(nil)
        lam.call('star_wars_movie_collection')
      end
    end
  end
end
