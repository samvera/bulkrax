# frozen_string_literal: true

require 'rails_helper'

# Consolidated contract for CSV import unzip / file placement.
#
# - `Bulkrax::Importer#importer_unzip_path` always returns
#   `File.join(parser.base_path, "import_#{path_string}")`, creates the dir
#   on `mkdir: true`, never returns nil, and is stable across calls.
#
# - `Bulkrax::CsvParser#unzip_with_primary_csv(zip_path)` (Case 3: single zip
#   containing a CSV) extracts the primary CSV to
#   `importer_unzip_path/{basename}` and every other entry to
#   `importer_unzip_path/files/{path_relative_to_primary_csv_dir}`.
#
# - `Bulkrax::CsvParser#unzip_attachments_only(zip_path)` (Case 2: separate
#   attachments zip accompanying an uploaded CSV) extracts every entry to
#   `importer_unzip_path/files/{path}`, stripping a single top-level wrapper
#   directory if present. CSVs inside the zip are treated as ordinary
#   attachments since the primary CSV was uploaded separately.
#
# These specs use real zip files in tmpdirs — `importer_unzip_path` is
# stubbed to a tmpdir (not to a dummy value) so `unzip_*` methods can
# actually write to the filesystem and we verify the resulting layout.
#
# Error cases use `raise_error` assertions — failures must be visible, not
# silent.
RSpec.describe Bulkrax::CsvParser do
  let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }
  subject(:parser) { described_class.new(importer) }

  # Each spec gets a fresh unzip_path backing directory.
  let(:unzip_dir) { File.realpath(Dir.mktmpdir) }
  before do
    dir = unzip_dir
    importer.define_singleton_method(:importer_unzip_path) do |mkdir: false|
      FileUtils.mkdir_p(dir) if mkdir
      dir
    end
  end
  after { FileUtils.rm_rf(unzip_dir) }

  # Builds a zip file with the given entries at `zip_path`.
  # `entries` is a Hash<String, String> mapping `entry_name => content`.
  def build_zip(zip_path, entries)
    Zip::File.open(zip_path, create: true) do |zip|
      entries.each do |name, content|
        next if name.end_with?('/')
        zip.get_output_stream(name) { |f| f.write(content) }
      end
    end
  end

  # Builds a temporary zip, yields its path, and cleans up afterward.
  def with_zip(entries)
    zip_file = Tempfile.new(['import', '.zip'])
    build_zip(zip_file.path, entries)
    yield zip_file.path
  ensure
    zip_file&.close!
  end

  describe '#unzip_with_primary_csv' do
    context 'flat zip: {metadata.csv, foo.jpg}' do
      it 'places the CSV at the unzip root and files under files/' do
        with_zip('metadata.csv' => 'header1,header2', 'foo.jpg' => 'jpg-bytes') do |zip_path|
          parser.unzip_with_primary_csv(zip_path)

          expect(File).to exist(File.join(unzip_dir, 'metadata.csv'))
          expect(File).to exist(File.join(unzip_dir, 'files', 'foo.jpg'))
          expect(File).not_to exist(File.join(unzip_dir, 'foo.jpg'))
        end
      end
    end

    context 'zip containing only a CSV (the staging bug — zip has no files alongside)' do
      # Regression coverage for the TypeError reported on staging:
      # `all_generic_no_files9.zip` contained only a CSV. The old
      # `normalize_unzipped_files_structure` moved the source zip into
      # files/, which broke the next `importer_unzip_path` call.
      it 'places the CSV at the unzip root and creates no files/ directory' do
        with_zip('metadata.csv' => 'header1,header2') do |zip_path|
          parser.unzip_with_primary_csv(zip_path)

          expect(File).to exist(File.join(unzip_dir, 'metadata.csv'))
          expect(File).not_to exist(File.join(unzip_dir, 'files'))
        end
      end
    end

    context 'zip with a single wrapper directory: {wrapper/metadata.csv, wrapper/files/foo.jpg}' do
      it 'strips the wrapper, placing the CSV at root and preserving files/ structure' do
        with_zip('wrapper/metadata.csv' => 'h1,h2', 'wrapper/files/foo.jpg' => 'jpg') do |zip_path|
          parser.unzip_with_primary_csv(zip_path)

          expect(File).to exist(File.join(unzip_dir, 'metadata.csv'))
          expect(File).to exist(File.join(unzip_dir, 'files', 'foo.jpg'))
        end
      end
    end

    context 'zip with a wrapper and nested non-files: {wrapper/metadata.csv, wrapper/subdir/foo.jpg}' do
      it 'places the CSV at root; non-primary entries land under files/ preserving relative structure' do
        with_zip('wrapper/metadata.csv' => 'h1,h2', 'wrapper/subdir/foo.jpg' => 'jpg') do |zip_path|
          parser.unzip_with_primary_csv(zip_path)

          expect(File).to exist(File.join(unzip_dir, 'metadata.csv'))
          expect(File).to exist(File.join(unzip_dir, 'files', 'subdir', 'foo.jpg'))
        end
      end
    end

    context 'zip with CSV at root + files in subdir: {metadata.csv, files/foo.jpg}' do
      it 'places the CSV at root and preserves files/ layout' do
        with_zip('metadata.csv' => 'h1,h2', 'files/foo.jpg' => 'jpg') do |zip_path|
          parser.unzip_with_primary_csv(zip_path)

          expect(File).to exist(File.join(unzip_dir, 'metadata.csv'))
          expect(File).to exist(File.join(unzip_dir, 'files', 'foo.jpg'))
        end
      end
    end

    context 'zip with primary CSV plus deeper non-primary CSVs: {wrapper/metadata.csv, wrapper/nested/other.csv}' do
      it 'treats only the shallowest CSV as primary; deeper CSVs go under files/' do
        with_zip('wrapper/metadata.csv' => 'primary', 'wrapper/nested/other.csv' => 'other') do |zip_path|
          parser.unzip_with_primary_csv(zip_path)

          expect(File).to exist(File.join(unzip_dir, 'metadata.csv'))
          expect(File).to exist(File.join(unzip_dir, 'files', 'nested', 'other.csv'))
        end
      end
    end

    context 'zip containing macOS junk' do
      it 'excludes __MACOSX/, .DS_Store, and ._* entries from extraction' do
        with_zip(
          'metadata.csv' => 'h1,h2',
          'files/foo.jpg' => 'jpg',
          '__MACOSX/files/._foo.jpg' => 'junk',
          '.DS_Store' => 'junk',
          'files/._foo.jpg' => 'junk'
        ) do |zip_path|
          parser.unzip_with_primary_csv(zip_path)

          expect(File).to exist(File.join(unzip_dir, 'metadata.csv'))
          expect(File).to exist(File.join(unzip_dir, 'files', 'foo.jpg'))
          expect(File).not_to exist(File.join(unzip_dir, '__MACOSX'))
          expect(File).not_to exist(File.join(unzip_dir, '.DS_Store'))
          expect(File).not_to exist(File.join(unzip_dir, 'files', '._foo.jpg'))
        end
      end
    end

    context 'when the zip contains no CSV' do
      it 'raises a visible error' do
        with_zip('foo.jpg' => 'jpg', 'bar.pdf' => 'pdf') do |zip_path|
          expect { parser.unzip_with_primary_csv(zip_path) }
            .to raise_error(/no csv/i)
        end
      end
    end

    context 'when multiple CSVs share the shallowest level (same directory)' do
      it 'raises a visible error' do
        with_zip('a.csv' => '1', 'b.csv' => '2', 'files/foo.jpg' => 'jpg') do |zip_path|
          expect { parser.unzip_with_primary_csv(zip_path) }
            .to raise_error(Bulkrax::UnzipError, /multiple csv/i)
        end
      end
    end

    context 'when multiple CSVs share the shallowest level (different directories)' do
      it 'raises a visible error' do
        with_zip('dir1/a.csv' => '1', 'dir2/b.csv' => '2') do |zip_path|
          expect { parser.unzip_with_primary_csv(zip_path) }
            .to raise_error(Bulkrax::UnzipError, /multiple csv/i)
        end
      end
    end

    context 'when the zip is empty of real entries (only junk)' do
      it 'raises a no-csv error' do
        with_zip('__MACOSX/foo' => 'junk', '.DS_Store' => 'junk') do |zip_path|
          expect { parser.unzip_with_primary_csv(zip_path) }
            .to raise_error(/no csv/i)
        end
      end
    end

    # Zip Slip defense (https://security.snyk.io/research/zip-slip-vulnerability).
    # A malicious zip can include entries whose names use `..` to escape
    # the extraction directory, or absolute paths that point elsewhere on
    # disk. Extraction must refuse such entries before writing anything.
    context 'when a zip contains a path-traversal entry (..)' do
      it 'raises UnzipError and writes nothing outside the extraction dir' do
        outside_dir = File.realpath(Dir.mktmpdir)
        with_zip('metadata.csv' => 'h1,h2', "../#{File.basename(outside_dir)}/evil.txt" => 'pwned') do |zip_path|
          expect { parser.unzip_with_primary_csv(zip_path) }
            .to raise_error(Bulkrax::UnzipError, /unsafe/i)

          expect(File).not_to exist(File.join(outside_dir, 'evil.txt'))
        end
      ensure
        FileUtils.rm_rf(outside_dir) if outside_dir
      end
    end
  end

  describe '#unzip_attachments_only' do
    context 'zip with flat files: {foo.jpg, bar.pdf}' do
      it 'places every entry under files/' do
        with_zip('foo.jpg' => 'jpg', 'bar.pdf' => 'pdf') do |zip_path|
          parser.unzip_attachments_only(zip_path)

          expect(File).to exist(File.join(unzip_dir, 'files', 'foo.jpg'))
          expect(File).to exist(File.join(unzip_dir, 'files', 'bar.pdf'))
        end
      end
    end

    context 'zip with a single files/ wrapper: {files/foo.jpg, files/bar.pdf}' do
      it 'strips the wrapper and places entries under files/ without doubling' do
        with_zip('files/foo.jpg' => 'jpg', 'files/bar.pdf' => 'pdf') do |zip_path|
          parser.unzip_attachments_only(zip_path)

          expect(File).to exist(File.join(unzip_dir, 'files', 'foo.jpg'))
          expect(File).to exist(File.join(unzip_dir, 'files', 'bar.pdf'))
          expect(File).not_to exist(File.join(unzip_dir, 'files', 'files', 'foo.jpg'))
        end
      end
    end

    context 'zip with a single arbitrary wrapper: {myfiles/foo.jpg}' do
      it 'strips the wrapper and places entries under files/' do
        with_zip('myfiles/foo.jpg' => 'jpg', 'myfiles/bar.pdf' => 'pdf') do |zip_path|
          parser.unzip_attachments_only(zip_path)

          expect(File).to exist(File.join(unzip_dir, 'files', 'foo.jpg'))
          expect(File).to exist(File.join(unzip_dir, 'files', 'bar.pdf'))
        end
      end
    end

    context 'zip with nested structure: {files/subdir/foo.jpg}' do
      it 'strips a single top-level wrapper and preserves deeper structure under files/' do
        with_zip('files/subdir/foo.jpg' => 'jpg') do |zip_path|
          parser.unzip_attachments_only(zip_path)

          expect(File).to exist(File.join(unzip_dir, 'files', 'subdir', 'foo.jpg'))
        end
      end
    end

    context 'zip with multiple top-level entries: {foo.jpg, subdir/bar.pdf}' do
      it 'does not strip (no single wrapper) and preserves structure under files/' do
        with_zip('foo.jpg' => 'jpg', 'subdir/bar.pdf' => 'pdf') do |zip_path|
          parser.unzip_attachments_only(zip_path)

          expect(File).to exist(File.join(unzip_dir, 'files', 'foo.jpg'))
          expect(File).to exist(File.join(unzip_dir, 'files', 'subdir', 'bar.pdf'))
        end
      end
    end

    context 'zip containing macOS junk' do
      it 'excludes junk entries' do
        with_zip(
          'foo.jpg' => 'jpg',
          '__MACOSX/foo' => 'junk',
          '.DS_Store' => 'junk',
          '._foo.jpg' => 'junk'
        ) do |zip_path|
          parser.unzip_attachments_only(zip_path)

          expect(File).to exist(File.join(unzip_dir, 'files', 'foo.jpg'))
          expect(File).not_to exist(File.join(unzip_dir, 'files', '__MACOSX'))
          expect(File).not_to exist(File.join(unzip_dir, 'files', '.DS_Store'))
          expect(File).not_to exist(File.join(unzip_dir, 'files', '._foo.jpg'))
        end
      end
    end

    context 'when the zip contains CSVs alongside other files' do
      # CSVs inside an attachments zip are legitimate — the user uploaded
      # the primary CSV separately, so any CSVs in the attachments zip are
      # just additional attachments (referenced by the primary CSV's file
      # column, same as JPGs or PDFs).
      it 'places CSV entries under files/ just like any other attachment' do
        with_zip('extra.csv' => 'h1,h2', 'foo.jpg' => 'jpg') do |zip_path|
          parser.unzip_attachments_only(zip_path)

          expect(File).to exist(File.join(unzip_dir, 'files', 'extra.csv'))
          expect(File).to exist(File.join(unzip_dir, 'files', 'foo.jpg'))
        end
      end
    end

    # Zip Slip defense — same protection as unzip_with_primary_csv.
    context 'when the zip contains a path-traversal entry (..)' do
      it 'raises UnzipError and writes nothing outside the extraction dir' do
        outside_dir = File.realpath(Dir.mktmpdir)
        with_zip('foo.jpg' => 'jpg', "../#{File.basename(outside_dir)}/evil.txt" => 'pwned') do |zip_path|
          expect { parser.unzip_attachments_only(zip_path) }
            .to raise_error(Bulkrax::UnzipError, /unsafe/i)

          expect(File).not_to exist(File.join(outside_dir, 'evil.txt'))
        end
      ensure
        FileUtils.rm_rf(outside_dir) if outside_dir
      end
    end
  end

  describe '#remove_spaces_from_filenames' do
    before { FileUtils.mkdir_p(File.join(unzip_dir, 'files')) }

    it 'renames files under files/ that contain spaces, replacing spaces with underscores' do
      File.write(File.join(unzip_dir, 'files', 'has space.jpg'), 'jpg')
      File.write(File.join(unzip_dir, 'files', 'no_space.jpg'), 'jpg')

      parser.remove_spaces_from_filenames

      expect(File).to exist(File.join(unzip_dir, 'files', 'has_space.jpg'))
      expect(File).not_to exist(File.join(unzip_dir, 'files', 'has space.jpg'))
      expect(File).to exist(File.join(unzip_dir, 'files', 'no_space.jpg'))
    end

    it 'is a no-op when no filenames contain spaces' do
      File.write(File.join(unzip_dir, 'files', 'alpha.jpg'), 'jpg')
      File.write(File.join(unzip_dir, 'files', 'beta.pdf'), 'pdf')

      expect { parser.remove_spaces_from_filenames }.not_to raise_error

      expect(File).to exist(File.join(unzip_dir, 'files', 'alpha.jpg'))
      expect(File).to exist(File.join(unzip_dir, 'files', 'beta.pdf'))
    end

    it 'only looks at the top level of files/ (nested files are not renamed)' do
      # Post-fix, nested files under files/subdir/ exist because the CSV
      # references paths like "subdir/file with space.jpg". Renaming nested
      # entries would break those references. Only the top-level files/
      # directory is rewritten — consistent with pre-1098 behavior.
      FileUtils.mkdir_p(File.join(unzip_dir, 'files', 'subdir'))
      File.write(File.join(unzip_dir, 'files', 'subdir', 'nested space.jpg'), 'jpg')

      parser.remove_spaces_from_filenames

      expect(File).to exist(File.join(unzip_dir, 'files', 'subdir', 'nested space.jpg'))
      expect(File).not_to exist(File.join(unzip_dir, 'files', 'subdir', 'nested_space.jpg'))
    end
  end
end

RSpec.describe Bulkrax::Importer, type: :model do
  describe '#importer_unzip_path' do
    let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }
    let(:expected_path) { File.join(importer.parser.base_path, "import_#{importer.path_string}") }

    after do
      FileUtils.rm_rf(expected_path) if Dir.exist?(expected_path)
    end

    it 'returns base_path/import_{path_string} regardless of whether the dir exists' do
      FileUtils.rm_rf(expected_path) if Dir.exist?(expected_path)
      expect(Dir.exist?(expected_path)).to be false

      expect(importer.importer_unzip_path).to eq(expected_path)
    end

    it 'never returns nil' do
      expect(importer.importer_unzip_path).to be_a(String)
      expect(importer.importer_unzip_path).not_to be_empty
    end

    it 'creates the directory when mkdir: true' do
      FileUtils.rm_rf(expected_path) if Dir.exist?(expected_path)

      importer.importer_unzip_path(mkdir: true)

      expect(Dir.exist?(expected_path)).to be true
    end

    it 'does not create the directory when mkdir: false (default)' do
      FileUtils.rm_rf(expected_path) if Dir.exist?(expected_path)

      importer.importer_unzip_path

      expect(Dir.exist?(expected_path)).to be false
    end

    it 'is stable across calls within one importer instance' do
      first = importer.importer_unzip_path
      second = importer.importer_unzip_path
      expect(first).to eq(second)
    end

    it 'does not return the directory containing the import_file_path zip' do
      # Prior (buggy) behavior returned File.dirname(import_file_path) when
      # import_file_path was a zip that existed on disk. The fix must not
      # return that directory — it must return the canonical import_* path.
      zip_tmp = Tempfile.new(['import', '.zip'])
      Zip::File.open(zip_tmp.path, create: true) { |z| z.get_output_stream('dummy') { |f| f.write('x') } }
      zip_tmp.close
      importer.parser_fields['import_file_path'] = zip_tmp.path

      expect(importer.importer_unzip_path).to eq(expected_path)
      expect(importer.importer_unzip_path).not_to eq(File.dirname(zip_tmp.path))
    ensure
      zip_tmp&.unlink
    end
  end
end
