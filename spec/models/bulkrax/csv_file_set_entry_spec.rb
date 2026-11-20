# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe CsvFileSetEntry, type: :model do
    subject(:entry) { described_class.new }

    describe '#default_work_type' do
      subject { entry.default_work_type }
      it { is_expected.to eq("FileSet") }
    end

    describe '#add_metadata_for_model' do
      context 'when the row says Hyrax::FileSet and file_model_class is FileSet' do
        before { entry.parsed_metadata = { 'model' => 'Hyrax::FileSet' } }

        it 'builds it as a file set, which requires a filename' do
          expect { entry.send(:add_metadata_for_model) }
            .to raise_error(FileSetEntryBehavior::FileNameError, 'File set must have a filename')
        end
      end
    end

    describe '#file_reference' do
      context 'when parsed_metadata includes the "file" property' do
        before do
          entry.parsed_metadata = { 'file' => ['test.png'] }
        end

        it 'returns the correct key' do
          expect(entry.file_reference).to eq('file')
        end
      end

      context 'when parsed_metadata includes the "remote_files" property' do
        before do
          entry.parsed_metadata = { 'remote_files' => ['test.png'] }
        end

        it 'returns the correct key' do
          expect(entry.file_reference).to eq('remote_files')
        end
      end
    end

    describe '#validate_presence_of_parent!' do
      context 'when parent is missing' do
        before do
          entry.parsed_metadata = { 'remote_files' => ['test.png'] }
          allow(entry).to receive(:related_parents_parsed_mapping).and_return('parents')
        end
        it 'raises an error' do
          # entry.validate_presence_of_parent!
          expect { entry.validate_presence_of_parent! }.to raise_error(FileSetEntryBehavior::OrphanFileSetError, 'File set must be related to at least one work')
        end
      end
    end

    describe '#add_path_to_file' do
      context 'when file is not present' do
        subject(:entry) { described_class.new(importerexporter: FactoryBot.create(:bulkrax_importer_csv), type: "Bulkrax::CsvFileSetEntry") }

        before do
          entry.parsed_metadata = { 'file' => ['test.png'] }
          allow(entry.parser).to receive(:importer_unzip_path).and_return('some_real_path')
        end
        it 'raises an error' do
          expect { entry.add_path_to_file }.to raise_error(FileSetEntryBehavior::FilePathError, 'one or more file paths are invalid: test.png')
        end
      end
    end

    describe '#validate_presence_of_filename!' do
      context 'when filename is missing' do
        before do
          entry.parsed_metadata = {}
        end

        it 'raises a FileNameError' do
          expect { entry.validate_presence_of_filename! }
            .to raise_error(FileSetEntryBehavior::FileNameError, 'File set must have a filename')
        end
      end

      context 'when filename is present' do
        before do
          entry.parsed_metadata = { 'file' => ['test.png'] }
        end

        it 'does not raise an error' do
          expect { entry.validate_presence_of_filename! }
            .not_to raise_error
        end
      end

      context 'when filename is an array containing an empty string' do
        before do
          entry.parsed_metadata = { 'file' => [''] }
        end

        it 'raises a FileNameError' do
          expect { entry.validate_presence_of_filename! }
            .to raise_error(FileSetEntryBehavior::FileNameError, 'File set must have a filename')
        end
      end
    end

    describe '#add_visibility' do
      subject(:entry) { described_class.new(importerexporter: importer, type: 'Bulkrax::CsvFileSetEntry') }
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv, parser_fields: { 'import_file_path' => 'spec/fixtures/csv/good.csv', 'visibility' => 'open' }) }
      let(:existing_record) { nil }
      # rubocop:disable RSpec/VerifiedDoubles
      let(:factory) { double('factory', find: existing_record) }
      # rubocop:enable RSpec/VerifiedDoubles

      before do
        entry.parsed_metadata = {}
        allow(entry).to receive(:factory).and_return(factory)
        allow(Bulkrax.object_factory).to receive(:file_sets_take_work_visibility?).and_return(takes_work_visibility)
      end

      context 'when new file sets take their work visibility' do
        let(:takes_work_visibility) { true }

        it "leaves a new file set's visibility to its work" do
          entry.add_visibility

          expect(entry.parsed_metadata['visibility']).to be_nil
        end

        context 'when the row updates an existing file set' do
          let(:existing_record) { Object.new }

          it "gives it the importer's visibility" do
            entry.add_visibility

            expect(entry.parsed_metadata['visibility']).to eq 'open'
          end
        end
      end

      context 'when new file sets do not take their work visibility' do
        let(:takes_work_visibility) { false }

        it "gives a new file set the importer's visibility" do
          entry.add_visibility

          expect(entry.parsed_metadata['visibility']).to eq 'open'
        end
      end
    end

    describe 'the factory import runs, after a visibility lookup' do
      subject(:entry) { described_class.new(importerexporter: importer, type: 'Bulkrax::CsvFileSetEntry', identifier: 'fs-1') }
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }

      before do
        entry.parsed_metadata = {}
        allow(Bulkrax.object_factory).to receive(:file_sets_take_work_visibility?).and_return(true)
        allow_any_instance_of(Bulkrax.object_factory).to receive(:find).and_return(nil) # rubocop:disable RSpec/AnyInstance
      end

      it 'is built from the metadata added after the lookup' do
        entry.add_visibility
        entry.parsed_metadata['title'] = ['A file set']

        expect(entry.factory.attributes['title']).to eq ['A file set']
      end
    end
  end
end
