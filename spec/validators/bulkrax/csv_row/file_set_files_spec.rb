# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::FileSetFiles do
  subject(:call) { described_class.call(record, 2, context) }

  let(:errors) { [] }
  let(:mappings) { { 'file' => { 'from' => ['file'], 'split' => '\\|' } } }
  let(:context) { { errors: errors, mappings: mappings } }
  let(:model) { Bulkrax.file_model_class.to_s }
  let(:record) { { source_identifier: 'fs-1', model: model, raw_row: raw_row } }

  before { allow(Bulkrax).to receive(:object_factory).and_return(Bulkrax::ValkyrieObjectFactory) }

  context 'when a file set row lists more than one file' do
    let(:raw_row) { { 'file' => 'first.png|second.png' } }

    it 'reports the row, as import fails it' do
      call

      expect(errors).to contain_exactly(
        hash_including(row: 2, source_identifier: 'fs-1', severity: 'error', category: 'more_than_one_file', column: 'file', value: '2',
                       message: 'This file set row lists 2 files; a file set row takes one.')
      )
    end
  end

  context 'when a file set row lists one file' do
    let(:raw_row) { { 'file' => 'first.png' } }

    it 'reports nothing' do
      call

      expect(errors).to be_empty
    end
  end

  context 'when a file set row lists the same file twice' do
    let(:raw_row) { { 'file' => 'first.png', 'file_2' => 'first.png' } }

    it 'reports nothing, as import keeps the file once' do
      call

      expect(errors).to be_empty
    end
  end

  context "when the file mapping's condition drops a cell" do
    let(:mappings) { { 'file' => { 'from' => ['file'], 'if' => ['match?', '\\.png$'] } } }
    let(:raw_row) { { 'file' => 'cover.png', 'file_2' => 'notes.txt' } }

    it 'counts only the files import keeps' do
      call

      expect(errors).to be_empty
    end
  end

  context 'when a file set row lists a file and a remote file' do
    let(:raw_row) { { 'file' => 'first.png', 'remote_files' => 'https://example.com/second.png' } }

    it 'reports the row, as import fails it' do
      call

      expect(errors).to contain_exactly(a_hash_including(category: 'more_than_one_file', value: '2'))
    end
  end

  context 'when a file set row has no model and the default work type is the file set model' do
    let(:model) { nil }
    let(:raw_row) { { 'file' => 'first.png|second.png' } }

    before { allow(Bulkrax).to receive(:default_work_type).and_return(Bulkrax.file_model_class.to_s) }

    it 'reports the row, as import makes it a file set and fails it' do
      call

      expect(errors).to contain_exactly(a_hash_including(category: 'more_than_one_file', value: '2'))
    end
  end

  context 'when the remote files mapping parses each url' do
    let(:mappings) { { 'remote_files' => { 'from' => ['remote_files'], 'split' => '\\|', 'parsed' => true } } }
    let(:raw_row) { { 'remote_files' => 'https://example.com/a.png|https://example.com/b.png' } }

    before { allow(Bulkrax::Importer).to receive(:safe_uri_filename) }

    it 'counts the urls without requesting them' do
      call

      expect(errors).to contain_exactly(a_hash_including(category: 'more_than_one_file', value: '2'))
      expect(Bulkrax::Importer).not_to have_received(:safe_uri_filename)
    end
  end

  context 'when a file set row spells its model with a space' do
    let(:model) { Bulkrax.file_model_class.to_s.underscore.tr('_', ' ') }
    let(:raw_row) { { 'file' => 'first.png|second.png' } }

    it 'reports the row, as import makes it a file set and fails it' do
      call

      expect(errors).to contain_exactly(a_hash_including(category: 'more_than_one_file', value: '2'))
    end
  end

  context 'when a work row lists more than one file' do
    let(:model) { 'GenericWork' }
    let(:raw_row) { { 'file' => 'first.png|second.png' } }

    it 'reports nothing, as a work makes a file set for each file' do
      call

      expect(errors).to be_empty
    end
  end
end
