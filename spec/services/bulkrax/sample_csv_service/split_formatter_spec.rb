# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::SampleCsvService::SplitFormatter do
  let(:formatter) { described_class.new }

  describe '#format' do
    context 'when split_value is nil' do
      it 'returns a message indicating property does not split' do
        result = formatter.format(nil)

        expect(result).to eq('Property does not split.')
      end
    end

    context 'when split_value is true' do
      it 'uses the default Bulkrax multi_value_element_split_on pattern' do
        allow(Bulkrax).to receive(:multi_value_element_split_on).and_return(/[|;]/)

        result = formatter.format(true)

        expect(result).to eq('Split multiple values with |, or ;')
      end
    end

    context 'when split_value is a string pattern' do
      it 'formats a single character pattern' do
        result = formatter.format('|')

        expect(result).to eq('Split multiple values with |')
      end

      it 'formats a character class pattern with multiple characters' do
        result = formatter.format('[|;]')

        expect(result).to eq('Split multiple values with |, or ;')
      end

      it 'formats an escaped character pattern' do
        result = formatter.format('\|')

        expect(result).to eq('Split multiple values with |')
      end
    end

    context 'when split_value is another type' do
      it 'returns the value unchanged' do
        result = formatter.format(123)

        expect(result).to eq(123)
      end
    end
  end
end
