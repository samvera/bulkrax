# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::FileReference do
  let(:context) do
    {
      errors: [],
      zip_plan: plan
    }
  end

  # Minimal plan stand-in; the validator only calls `available_paths`.
  def build_plan(*paths)
    Struct.new(:available_paths).new(paths)
  end

  describe '.call' do
    context 'when no zip plan is present' do
      let(:plan) { nil }

      it 'emits no errors even if the record references files' do
        record = { source_identifier: 'w1', file_values: ['foo.jpg'] }
        described_class.call(record, 2, context)
        expect(context[:errors]).to be_empty
      end
    end

    context 'when the record references no files' do
      let(:plan) { build_plan('foo.jpg') }

      it 'emits no errors for a blank file value' do
        described_class.call({ source_identifier: 'w1', file_values: [] }, 2, context)
        expect(context[:errors]).to be_empty
      end

      it 'emits no errors when the row has no file values' do
        described_class.call({ source_identifier: 'w1' }, 2, context)
        expect(context[:errors]).to be_empty
      end
    end

    context 'exact-path match' do
      let(:plan) { build_plan('subdir/foo.jpg', 'bar.pdf') }

      it 'passes for a bare filename that matches a root-level entry' do
        described_class.call({ source_identifier: 'w1', file_values: ['bar.pdf'] }, 2, context)
        expect(context[:errors]).to be_empty
      end

      it 'passes for a full relative path that matches a nested entry' do
        described_class.call({ source_identifier: 'w1', file_values: ['subdir/foo.jpg'] }, 2, context)
        expect(context[:errors]).to be_empty
      end
    end

    context 'subdirectory mismatch (CSV `subdir_a/foo.jpg`, zip `subdir_b/foo.jpg`)' do
      let(:plan) { build_plan('subdir_b/foo.jpg') }

      it 'emits a missing_file_reference error' do
        described_class.call({ source_identifier: 'w1', file_values: ['subdir_a/foo.jpg'] }, 2, context)
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
        described_class.call({ source_identifier: 'w1', file_values: ['foo.jpg'] }, 2, context)
        expect(context[:errors]).to contain_exactly(
          a_hash_including(category: 'missing_file_reference', value: 'foo.jpg')
        )
      end
    end

    # Bare filename that only matches a nested entry: validator reports
    # missing because import does not do basename fallback: it joins the
    # path with files/ and demands an exact match.
    context 'bare filename where zip has two copies at different depths' do
      let(:plan) { build_plan('dir_a/foo.jpg', 'dir_b/foo.jpg') }

      it 'emits a missing_file_reference error' do
        described_class.call({ source_identifier: 'w1', file_values: ['foo.jpg'] }, 2, context)
        expect(context[:errors]).to contain_exactly(
          a_hash_including(category: 'missing_file_reference', value: 'foo.jpg')
        )
      end
    end

    context 'multi-value cell (pipe-delimited) with one missing' do
      let(:plan) { build_plan('present.jpg') }

      it 'emits one error for the missing value only' do
        described_class.call({ source_identifier: 'w1', file_values: ['present.jpg|missing.jpg'] }, 2, context)
        expect(context[:errors]).to contain_exactly(
          a_hash_including(category: 'missing_file_reference', value: 'missing.jpg')
        )
      end
    end

    context 'multiple aliased columns with values in separate array elements' do
      let(:plan) { build_plan('present.jpg') }

      it 'checks each array element independently' do
        # e.g., mapping `file: from: ['item','file']`, row has item and file populated
        described_class.call({ source_identifier: 'w1', file_values: ['present.jpg', 'missing.jpg'] }, 2, context)
        expect(context[:errors]).to contain_exactly(
          a_hash_including(category: 'missing_file_reference', value: 'missing.jpg')
        )
      end
    end
  end

  describe 'matching references the way the importer finds files' do
    def errors_for(reference, *zip_paths)
      ctx = { errors: [], zip_plan: build_plan(*zip_paths) }
      described_class.call({ source_identifier: 'w1', file_values: [reference] }, 2, ctx)
      ctx[:errors]
    end

    it 'accepts a reference with spaces when the zip has the underscored name' do
      expect(errors_for('my file.jpg', 'my_file.jpg')).to be_empty
    end

    it 'accepts an underscored reference to a top-level entry the importer renames' do
      expect(errors_for('my_file.jpg', 'my file.jpg')).to be_empty
    end

    it 'accepts a leading ./ or / the importer resolves' do
      expect(errors_for('./foo.jpg', 'foo.jpg')).to be_empty
      expect(errors_for('/foo.jpg', 'foo.jpg')).to be_empty
    end

    it 'accepts a nested reference whose top-level folder the importer renames' do
      expect(errors_for('my dir/a b.jpg', 'my dir/a b.jpg')).to be_empty
    end

    it 'rejects a nested reference that differs from the zip only by underscores' do
      expect(errors_for('scans/my photo.jpg', 'scans/my_photo.jpg')).not_to be_empty
      expect(errors_for('scans/my_photo.jpg', 'scans/my photo.jpg')).not_to be_empty
    end

    it 'matches a non-ASCII name against the raw bytes the zip reports' do
      expect(errors_for('café.jpg', 'café.jpg'.b)).to be_empty
    end

    it 'keeps a hidden top-level name as written, since import does not rename it' do
      expect(errors_for('.hidden file.jpg', '.hidden file.jpg')).to be_empty
      expect(errors_for('.hidden_file.jpg', '.hidden file.jpg')).not_to be_empty
    end

    it 'rejects a reference ending in / or /. that import cannot open' do
      expect(errors_for('photo.jpg/', 'photo.jpg')).not_to be_empty
      expect(errors_for('photo.jpg/.', 'photo.jpg')).not_to be_empty
    end

    it 'builds the path set once per validation run' do
      plan = build_plan('a.jpg')
      ctx = { errors: [], zip_plan: plan }
      expect(plan).to receive(:available_paths).once.and_call_original
      2.times { |i| described_class.call({ source_identifier: "w#{i}", file_values: ['a.jpg'] }, i + 2, ctx) }
    end
  end
end
