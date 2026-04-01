# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::CircularReference do
  def make_context(graph)
    { errors: [], relationship_graph: graph }
  end

  def make_record(source_identifier)
    { source_identifier: source_identifier }
  end

  def call(record, context, row: 2)
    described_class.call(record, row, context)
  end

  # ─── detect_cycle_ids ────────────────────────────────────────────────────────

  describe '.detect_cycle_ids (via call)' do
    context 'with no relationships' do
      it 'produces no errors' do
        ctx = make_context('work1' => [], 'work2' => [])
        call(make_record('work1'), ctx)
        expect(ctx[:errors]).to be_empty
      end
    end

    context 'with a simple linear chain (no cycle)' do
      # col1 ← work1 ← work2  (work1 has parent col1, work2 has parent work1)
      it 'produces no errors' do
        graph = { 'col1' => [], 'work1' => ['col1'], 'work2' => ['work1'] }
        ctx = make_context(graph)
        %w[col1 work1 work2].each { |id| call(make_record(id), ctx) }
        expect(ctx[:errors]).to be_empty
      end
    end

    context 'with a direct self-reference (A → A)' do
      it 'flags the self-referencing record' do
        ctx = make_context('work1' => ['work1'])
        call(make_record('work1'), ctx)
        expect(ctx[:errors].length).to eq(1)
        expect(ctx[:errors].first[:source_identifier]).to eq('work1')
        expect(ctx[:errors].first[:category]).to eq('circular_reference')
      end
    end

    context 'with a two-node cycle (A → B → A)' do
      it 'flags both records in the cycle' do
        graph = { 'work1' => ['work2'], 'work2' => ['work1'] }
        ctx = make_context(graph)
        call(make_record('work1'), ctx, row: 2)
        call(make_record('work2'), ctx, row: 3)
        ids = ctx[:errors].map { |e| e[:source_identifier] }
        expect(ids).to contain_exactly('work1', 'work2')
      end
    end

    context 'with a three-node cycle (A → B → C → A)' do
      it 'flags all three records' do
        graph = { 'a' => ['c'], 'b' => ['a'], 'c' => ['b'] }
        ctx = make_context(graph)
        %w[a b c].each_with_index { |id, i| call(make_record(id), ctx, row: i + 2) }
        ids = ctx[:errors].map { |e| e[:source_identifier] }
        expect(ids).to contain_exactly('a', 'b', 'c')
      end
    end

    context 'with a cycle on a branch (D → E → F → E)' do
      it 'flags only the nodes in the cycle, not the entry node' do
        # D has parent E; E has parent F; F has parent E → cycle between E and F
        graph = { 'd' => ['e'], 'e' => ['f'], 'f' => ['e'] }
        ctx = make_context(graph)
        %w[d e f].each_with_index { |id, i| call(make_record(id), ctx, row: i + 2) }
        ids = ctx[:errors].map { |e| e[:source_identifier] }
        expect(ids).to include('e', 'f')
        expect(ids).not_to include('d')
      end
    end

    context 'with a cycle and unrelated records' do
      it 'does not flag records outside the cycle' do
        graph = { 'col1' => [], 'work1' => ['col1'], 'a' => ['b'], 'b' => ['a'] }
        ctx = make_context(graph)
        %w[col1 work1 a b].each_with_index { |id, i| call(make_record(id), ctx, row: i + 2) }
        ids = ctx[:errors].map { |e| e[:source_identifier] }
        expect(ids).to contain_exactly('a', 'b')
      end
    end
  end

  # ─── caching ─────────────────────────────────────────────────────────────────

  describe 'cycle detection caching' do
    it 'only detects cycles once per context and reuses the result' do
      graph = { 'a' => ['b'], 'b' => ['a'] }
      ctx = make_context(graph)

      expect(described_class).to receive(:detect_cycle_ids).once.and_call_original

      call(make_record('a'), ctx, row: 2)
      call(make_record('b'), ctx, row: 3)
    end
  end

  # ─── error shape ─────────────────────────────────────────────────────────────

  describe 'error message content' do
    it 'includes the expected keys' do
      ctx = make_context('work1' => ['work1'])
      call(make_record('work1'), ctx)
      error = ctx[:errors].first
      expect(error).to include(
        row: 2,
        source_identifier: 'work1',
        severity: 'error',
        category: 'circular_reference'
      )
      expect(error[:message]).to be_present
      expect(error[:suggestion]).to be_present
    end
  end

  # ─── empty graph ─────────────────────────────────────────────────────────────

  describe 'when relationship_graph is absent from context' do
    it 'does not raise and adds no errors' do
      ctx = { errors: [] }
      expect { call(make_record('work1'), ctx) }.not_to raise_error
      expect(ctx[:errors]).to be_empty
    end
  end
end
