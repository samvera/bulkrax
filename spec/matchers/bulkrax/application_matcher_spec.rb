# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ApplicationMatcher do
    describe 'handling the split argument' do
      it 'default split' do
        matcher = described_class.new(split: true)
        result = matcher.result(nil, " hey ; how : are | you")
        expect(result).to eq(["hey", "how", "are", "you"])
      end

      it 'custom regex split' do
        matcher = described_class.new(split: /\s*[;]\s*/)
        result = matcher.result(nil, " hey ; how : are | you")
        expect(result).to eq(["hey", "how : are | you"])
      end

      it 'no split' do
        matcher = described_class.new(split: false)
        result = matcher.result(nil, " hey ; how : are | you")
        expect(result).to eq("hey ; how : are | you")
      end

      it 'custom split' do
        matcher = described_class.new(split: '\|')
        result = matcher.result(nil, " hey ; how : are | you")
        expect(result).to eq(["hey ; how : are", "you"])
      end
    end

    describe '#parse_subject' do
      subject(:matcher) { described_class.new(to: 'subject', parsed: true, split: nil, if: nil, excluded: false, nested_type: nil) }

      it 'sentence-cases plain text subjects' do
        expect(matcher.parse_subject('photography')).to eq('Photography')
      end

      it 'sentence-cases multi-word plain text' do
        expect(matcher.parse_subject('CIVIL WAR')).to eq('Civil war')
      end

      it 'preserves http URIs verbatim' do
        uri = 'http://id.loc.gov/authorities/subjects/sh85101348'
        expect(matcher.parse_subject(uri)).to eq(uri)
      end

      it 'preserves https URIs verbatim' do
        uri = 'https://id.loc.gov/authorities/subjects/sh85101348'
        expect(matcher.parse_subject(uri)).to eq(uri)
      end

      it 'keeps the scheme lowercase so downstream URI matching works' do
        result = matcher.parse_subject('http://id.loc.gov/authorities/subjects/sh85101348')
        expect(result).to start_with('http://')
      end

      it 'keeps the https scheme lowercase so downstream URI matching works' do
        result = matcher.parse_subject('https://id.loc.gov/authorities/subjects/sh85101348')
        expect(result).to start_with('https://')
      end

      it 'normalizes a capitalized Http scheme' do
        result = matcher.parse_subject('Http://id.loc.gov/authorities/subjects/sh85101348')
        expect(result).to start_with('http://')
      end

      it 'normalizes a capitalized Https scheme' do
        result = matcher.parse_subject('Https://id.loc.gov/authorities/subjects/sh85101348')
        expect(result).to start_with('https://')
      end

      it 'downcases only the scheme of an all-caps URI, preserving the path' do
        result = matcher.parse_subject('HTTP://ID.LOC.GOV/AUTHORITIES/SUBJECTS/SH85101348')
        expect(result).to start_with('http://')
        expect(result).to eq('http://ID.LOC.GOV/AUTHORITIES/SUBJECTS/SH85101348')
      end

      it 'strips whitespace from URIs' do
        expect(matcher.parse_subject('  http://id.loc.gov/authorities/subjects/sh85101348  '))
          .to eq('http://id.loc.gov/authorities/subjects/sh85101348')
      end

      it 'returns nil for blank values' do
        expect(matcher.parse_subject('')).to be_nil
      end
    end
  end
end
