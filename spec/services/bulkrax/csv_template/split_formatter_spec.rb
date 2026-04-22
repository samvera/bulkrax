# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvTemplate::SplitFormatter do
  let(:formatter) { described_class.new }

  describe '#format' do
    context 'when split_value is nil' do
      it 'returns a message indicating property does not split' do
        result = formatter.format(nil)

        expect(result).to eq('Property does not split.')
      end
    end

    # Output rules (see SplitFormatter#format_message):
    #   1 delimiter  → "Split multiple values with X"
    #   2 delimiters → "Split multiple values with X or Y"
    #   3+ delimiters → "Split multiple values with X Y or Z"
    # Spaces — not commas — between delimiters, so the message stays
    # unambiguous when one of the delimiters IS a comma.
    context 'when split_value is true' do
      it 'uses the default Bulkrax multi_value_element_split_on pattern' do
        allow(Bulkrax).to receive(:multi_value_element_split_on).and_return(/[|;]/)

        result = formatter.format(true)

        expect(result).to eq('Split multiple values with | or ;')
      end
    end

    context 'when split_value is a string pattern' do
      it 'formats a single character pattern' do
        result = formatter.format('|')

        expect(result).to eq('Split multiple values with |')
      end

      it 'formats a two-char character class' do
        result = formatter.format('[|;]')

        expect(result).to eq('Split multiple values with | or ;')
      end

      it 'formats a three-char character class using spaces' do
        result = formatter.format('[:;|]')

        expect(result).to eq('Split multiple values with : ; or |')
      end

      it 'formats correctly when a delimiter is itself a comma' do
        # This is precisely why the joiner is a space: "|, ," would be ambiguous.
        result = formatter.format('[|,]')

        expect(result).to eq('Split multiple values with | or ,')
      end

      it 'formats an escaped character pattern' do
        result = formatter.format('\|')

        expect(result).to eq('Split multiple values with |')
      end
    end

    context 'when split_value is a Regexp' do
      # Hosts may set split to a live Regexp (not just a String). Previously
      # this fell through to the `else` branch and produced an inspect-style
      # dump; now the formatter parses the Regexp's source like a String.
      it 'formats a two-char character-class Regexp' do
        expect(formatter.format(/[|;]/)).to eq('Split multiple values with | or ;')
      end

      it 'formats an escaped single-char Regexp' do
        expect(formatter.format(/\|/)).to eq('Split multiple values with |')
      end

      it 'formats the default multi-value split Regexp' do
        # /\s*[:;|]\s*/ is the gem-wide default — the most common case users
        # see on the CSV template download. Without the punctuation fix this
        # previously rendered as "Split multiple values with : ;, or |".
        expect(formatter.format(/\s*[:;|]\s*/)).to eq('Split multiple values with : ; or |')
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
