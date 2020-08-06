# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ApplicationMatcher do
    describe 'handling the split argument' do
      it 'default split' do
        matcher = ApplicationMatcher.new(split: true)
        result = matcher.result(nil, " hey ; how : are | you")
        expect(result).to eq(["hey", "how", "are", "you"])
      end

      it 'custom regex split' do
        matcher = ApplicationMatcher.new(split: /\s*[;]\s*/)
        result = matcher.result(nil, " hey ; how : are | you")
        expect(result).to eq(["hey", "how : are | you"])
      end

      it 'no split' do
        matcher = ApplicationMatcher.new(split: false)
        result = matcher.result(nil, " hey ; how : are | you")
        expect(result).to eq("hey ; how : are | you")
      end

      it 'custom split' do
        matcher = ApplicationMatcher.new(split: '\|')
        result = matcher.result(nil, " hey ; how : are | you")
        expect(result).to eq(["hey ; how : are", "you"])
      end
    end
  end
end
