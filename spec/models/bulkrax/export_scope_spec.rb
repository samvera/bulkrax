# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::ExportScope do
  let(:user) { User.new(email: 'user@example.com') }
  let(:ability) { Ability.new(user) }

  subject(:scope) { described_class.new(ability) }

  describe '#current_ability' do
    it 'returns the ability passed to the constructor' do
      expect(scope.current_ability).to eq(ability)
    end
  end

  describe '#blacklight_config' do
    it 'returns a Blacklight::Configuration' do
      expect(scope.blacklight_config).to be_a(Blacklight::Configuration)
    end

    it 'is memoized' do
      expect(scope.blacklight_config).to be(scope.blacklight_config)
    end
  end
end
