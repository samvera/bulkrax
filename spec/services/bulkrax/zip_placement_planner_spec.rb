# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::ZipPlacementPlanner do
  # A lightweight stand-in for a Zip::Entry — the planner only reads
  # `name`, so anything with a `name` attribute suffices.
  Entry = Struct.new(:name)

  def entry(name)
    Entry.new(name)
  end

  describe '.plan with mode: :primary_csv' do
    context 'flat zip {metadata.csv, foo.jpg}' do
      let(:entries) { [entry('metadata.csv'), entry('foo.jpg')] }

      it 'primary extracts to root; other entries land under files/' do
        plan = described_class.plan(entries, mode: :primary_csv)
        expect(plan.primary_csv_entry.name).to eq('metadata.csv')
        expect(plan.placements.values).to contain_exactly('metadata.csv', 'files/foo.jpg')
      end

      it 'available_paths lists only non-CSV destinations under files/' do
        plan = described_class.plan(entries, mode: :primary_csv)
        expect(plan.available_paths).to contain_exactly('foo.jpg')
      end
    end

    context 'zip with a single wrapper directory {wrapper/metadata.csv, wrapper/files/foo.jpg}' do
      let(:entries) { [entry('wrapper/metadata.csv'), entry('wrapper/files/foo.jpg')] }

      it 'strips both the wrapper and the internal `files/` prefix' do
        plan = described_class.plan(entries, mode: :primary_csv)
        expect(plan.placements.values).to contain_exactly('metadata.csv', 'files/foo.jpg')
        expect(plan.available_paths).to contain_exactly('foo.jpg')
      end
    end

    context 'zip with CSV at root + nested file {metadata.csv, files/subdir/foo.jpg}' do
      let(:entries) { [entry('metadata.csv'), entry('files/subdir/foo.jpg')] }

      it 'preserves the nested path under files/' do
        plan = described_class.plan(entries, mode: :primary_csv)
        expect(plan.available_paths).to contain_exactly('subdir/foo.jpg')
      end
    end

    context 'when no CSV is present' do
      it 'raises Bulkrax::UnzipError' do
        expect { described_class.plan([entry('foo.jpg')], mode: :primary_csv) }
          .to raise_error(Bulkrax::UnzipError, /no_csv|No CSV/i)
      end
    end

    context 'when multiple CSVs share the shallowest level' do
      it 'raises Bulkrax::UnzipError' do
        entries = [entry('data1.csv'), entry('data2.csv')]
        expect { described_class.plan(entries, mode: :primary_csv) }
          .to raise_error(Bulkrax::UnzipError, /multiple_csv|Multiple CSV/i)
      end
    end
  end

  describe '.plan with mode: :attachments_only' do
    context 'flat zip {foo.jpg, bar.pdf}' do
      let(:entries) { [entry('foo.jpg'), entry('bar.pdf')] }

      it 'places every entry under files/ with no primary CSV' do
        plan = described_class.plan(entries, mode: :attachments_only)
        expect(plan.primary_csv_entry).to be_nil
        expect(plan.placements.values).to contain_exactly('files/foo.jpg', 'files/bar.pdf')
        expect(plan.available_paths).to contain_exactly('foo.jpg', 'bar.pdf')
      end
    end

    context 'zip with a single top-level wrapper {wrapper/foo.jpg, wrapper/bar.pdf}' do
      let(:entries) { [entry('wrapper/foo.jpg'), entry('wrapper/bar.pdf')] }

      it 'strips the wrapper so files land at files/foo.jpg, files/bar.pdf' do
        plan = described_class.plan(entries, mode: :attachments_only)
        expect(plan.available_paths).to contain_exactly('foo.jpg', 'bar.pdf')
      end
    end

    context 'zip with mixed top-level entries (no wrapper to strip)' do
      let(:entries) { [entry('foo.jpg'), entry('subdir/bar.pdf')] }

      it 'preserves all paths under files/' do
        plan = described_class.plan(entries, mode: :attachments_only)
        expect(plan.available_paths).to contain_exactly('foo.jpg', 'subdir/bar.pdf')
      end
    end
  end

  describe '.plan with an unknown mode' do
    it 'raises ArgumentError' do
      expect { described_class.plan([], mode: :garbage) }.to raise_error(ArgumentError, /Unknown mode/)
    end
  end
end
