# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::ExportSearchBuilder do
  subject(:builder) { described_class.new(scope) }

  let(:user) { User.new(email: 'user@example.com') }
  let(:ability) { Ability.new(user) }
  let(:scope) { Bulkrax::ExportScope.new(ability) }

  describe '#to_h' do
    it 'returns a hash with fq access control filters' do
      result = builder.to_h
      expect(result[:fq]).to be_an(Array)
      expect(result[:fq].join).to include('read_access')
    end
  end
end
