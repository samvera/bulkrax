# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe CsvFileSetEntry, type: :model do
    subject(:entry) { described_class.new }

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

    describe '#validate_presence_of_filename!' do
      context 'when filename is missing' do
        before do
          entry.parsed_metadata = {}
        end

        it 'raises a StandardError' do
          expect { entry.validate_presence_of_filename! }
            .to raise_error(StandardError, 'File set must have a filename')
        end
      end

      context 'when filename is present' do
        before do
          entry.parsed_metadata = { 'file' => ['test.png'] }
        end

        it 'does not raise a StandardError' do
          expect { entry.validate_presence_of_filename! }
            .not_to raise_error(StandardError)
        end
      end

      context 'when filename is an array containing an empty string' do
        before do
          entry.parsed_metadata = { 'file' => [''] }
        end

        it 'raises a StandardError' do
          expect { entry.validate_presence_of_filename! }
            .to raise_error(StandardError, 'File set must have a filename')
        end
      end
    end
  end
end
