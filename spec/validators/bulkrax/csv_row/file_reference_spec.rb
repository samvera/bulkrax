# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::FileReference do
  let(:context) do
    {
      errors: [],
      zip_plan: plan
    }
  end

  # Minimal plan stand-in — the validator only calls `available_paths`.
  def build_plan(*paths)
    Struct.new(:available_paths).new(paths)
  end

  describe '.call' do
    context 'when no zip plan is present' do
      let(:plan) { nil }

      it 'emits no errors even if the record references files' do
        record = { source_identifier: 'w1', file: ['foo.jpg'] }
        described_class.call(record, 2, context)
        expect(context[:errors]).to be_empty
      end
    end

    context 'when the record references no files' do
      let(:plan) { build_plan('foo.jpg') }

      it 'emits no errors for a blank file value' do
        described_class.call({ source_identifier: 'w1', file: [] }, 2, context)
        expect(context[:errors]).to be_empty
      end

      it 'emits no errors for a missing :file key' do
        described_class.call({ source_identifier: 'w1' }, 2, context)
        expect(context[:errors]).to be_empty
      end
    end

    context 'exact-path match' do
      let(:plan) { build_plan('subdir/foo.jpg', 'bar.pdf') }

      it 'passes for a bare filename that matches a root-level entry' do
        described_class.call({ source_identifier: 'w1', file: ['bar.pdf'] }, 2, context)
        expect(context[:errors]).to be_empty
      end

      it 'passes for a full relative path that matches a nested entry' do
        described_class.call({ source_identifier: 'w1', file: ['subdir/foo.jpg'] }, 2, context)
        expect(context[:errors]).to be_empty
      end
    end

    # These are the three cases FileValidator silently passes today and
    # that import later fails on.
    context 'subdirectory mismatch (CSV `subdir_a/foo.jpg`, zip `subdir_b/foo.jpg`)' do
      let(:plan) { build_plan('subdir_b/foo.jpg') }

      it 'emits a missing_file_reference error' do
        described_class.call({ source_identifier: 'w1', file: ['subdir_a/foo.jpg'] }, 2, context)
        expect(context[:errors]).to contain_exactly(
          a_hash_including(
            row: 2,
            source_identifier: 'w1',
            severity: 'error',
            category: 'missing_file_reference',
            column: 'file',
            value: 'subdir_a/foo.jpg'
          )
        )
      end
    end

    context 'root/nested mismatch (CSV bare `foo.jpg`, zip has only `deep/nested/foo.jpg`)' do
      let(:plan) { build_plan('deep/nested/foo.jpg') }

      it 'emits a missing_file_reference error' do
        described_class.call({ source_identifier: 'w1', file: ['foo.jpg'] }, 2, context)
        expect(context[:errors]).to contain_exactly(
          a_hash_including(category: 'missing_file_reference', value: 'foo.jpg')
        )
      end
    end

    # Bare filename that only matches a nested entry: validator reports
    # missing because import does not do basename fallback — it joins the
    # path with files/ and demands an exact match.
    context 'bare filename where zip has two copies at different depths' do
      let(:plan) { build_plan('dir_a/foo.jpg', 'dir_b/foo.jpg') }

      it 'emits a missing_file_reference error' do
        described_class.call({ source_identifier: 'w1', file: ['foo.jpg'] }, 2, context)
        expect(context[:errors]).to contain_exactly(
          a_hash_including(category: 'missing_file_reference', value: 'foo.jpg')
        )
      end
    end

    context 'multi-value cell (pipe-delimited) with one missing' do
      let(:plan) { build_plan('present.jpg') }

      it 'emits one error for the missing value only' do
        # record[:file] shape mirrors post-Stage-1 parse_validation_rows: an
        # Array of raw cell strings, one per aliased column.
        described_class.call({ source_identifier: 'w1', file: ['present.jpg|missing.jpg'] }, 2, context)
        expect(context[:errors]).to contain_exactly(
          a_hash_including(category: 'missing_file_reference', value: 'missing.jpg')
        )
      end
    end

    context 'multiple aliased columns — values in separate array elements' do
      let(:plan) { build_plan('present.jpg') }

      it 'checks each array element independently' do
        # e.g., mapping `file: from: ['item','file']`, row has item and file populated
        described_class.call({ source_identifier: 'w1', file: ['present.jpg', 'missing.jpg'] }, 2, context)
        expect(context[:errors]).to contain_exactly(
          a_hash_including(category: 'missing_file_reference', value: 'missing.jpg')
        )
      end
    end
  end
end
