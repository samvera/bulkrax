# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::SplitPatternCoercion do
  describe '.coerce' do
    it 'returns nil for nil' do
      expect(described_class.coerce(nil)).to be_nil
    end

    it 'returns nil for an empty string' do
      expect(described_class.coerce('')).to be_nil
    end

    it 'returns Bulkrax.multi_value_element_split_on when given true' do
      expect(described_class.coerce(true)).to eq(Bulkrax.multi_value_element_split_on)
    end

    it 'returns a Regexp argument unchanged' do
      pattern = /\s*,\s*/
      expect(described_class.coerce(pattern)).to equal(pattern)
    end

    it 'returns non-string, non-regexp values unchanged' do
      # Defensive: unusual values (Arrays, Symbols, etc.) shouldn't blow up.
      expect(described_class.coerce(:some_symbol)).to eq(:some_symbol)
    end

    context 'when given a String' do
      # String is treated as a regex source to match the long-standing
      # contract in Bulkrax::ApplicationMatcher#process_split.
      {
        '\\|' => ['a|b', %w[a b]], # plain pipe
        ',' => ['a,b,c', %w[a b c]],
        '\\s*;\\s*' => ['a ; b ;c', %w[a b c]],
        '(?-mix:\\s*[;|]\\s*)' => ['coll1 | coll2', %w[coll1 coll2]], # serialised Regexp
        '(?i-mx:\\AFOO\\z)' => ['FOO', []] # serialised flagged Regexp
      }.each do |src, (sample, expected)|
        it "builds a Regexp from #{src.inspect} that splits #{sample.inspect} → #{expected.inspect}" do
          result = described_class.coerce(src)
          expect(result).to be_a(Regexp)
          expect(sample.split(result)).to eq(expected)
        end
      end

      it 'returns the original String when the source is not a valid Regexp' do
        # e.g. a stray unclosed group. We don't raise, we just pass it through.
        bad = '('
        expect(described_class.coerce(bad)).to eq(bad)
      end
    end
  end
end
