# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::SampleCsvService::ColumnDescriptor do
  let(:descriptor) { described_class.new }

  describe 'COLUMN_DESCRIPTIONS' do
    it 'contains the expected groups' do
      expect(described_class::COLUMN_DESCRIPTIONS).to have_key(:highlighted)
      expect(described_class::COLUMN_DESCRIPTIONS).to have_key(:visibility)
      expect(described_class::COLUMN_DESCRIPTIONS).to have_key(:files)
    end

    it 'has frozen constant to prevent modifications' do
      expect(described_class::COLUMN_DESCRIPTIONS).to be_frozen
    end
  end

  describe '#core_columns' do
    it 'returns highlighted and visibility columns combined' do
      result = descriptor.core_columns

      expect(result).to be_an(Array)
      expect(result).to include('work_type', 'source_identifier', 'id', 'rights_statement')
      expect(result).to include('visibility', 'embargo_release_date', 'visibility_during_embargo')
    end

    it 'returns columns in the correct order' do
      result = descriptor.core_columns

      # Highlighted columns should come first
      highlighted_count = described_class::COLUMN_DESCRIPTIONS[:highlighted].length
      visibility_start = highlighted_count

      expect(result[0]).to eq('work_type')
      expect(result[visibility_start]).to eq('visibility')
    end

    it 'returns all core columns without duplicates' do
      result = descriptor.core_columns

      expected_count = described_class::COLUMN_DESCRIPTIONS[:highlighted].length +
                      described_class::COLUMN_DESCRIPTIONS[:visibility].length

      expect(result.length).to eq(expected_count)
      expect(result.uniq).to eq(result)
    end
  end

  describe '#find_description_for' do
    context 'with highlighted columns' do
      it 'finds description for work_type' do
        description = descriptor.find_description_for('work_type')

        expect(description).to include('work types configured')
        # The default work type is interpolated when the constant is defined
        # so we just check that it includes the expected pattern
        expect(description).to match(/If left blank, your default work type, .+, is used/)
      end
    end

    context 'with visibility columns' do
      it 'finds description for visibility' do
        description = descriptor.find_description_for('visibility')

        expect(description).to include('open, institution, restricted, embargo, lease')
      end
    end

    context 'with file columns' do
      it 'finds description for file' do
        description = descriptor.find_description_for('file')

        expect(description).to include('filenames exactly matching')
      end
    end

    context 'with unknown column' do
      it 'returns nil for unknown column' do
        description = descriptor.find_description_for('unknown_column')

        expect(description).to be_nil
      end
    end
  end
end
