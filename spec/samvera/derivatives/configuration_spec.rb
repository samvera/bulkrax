# frozen_string_literal: true

require 'spec_helper'
require 'samvera/derivatives/configuration'

RSpec.describe Samvera::Derivatives::Configuration do
  let(:file_set) { double(:file_set) }
  let(:config) { described_class.new }

  describe '#registry_for' do
    it 'has a applicable_for that is falsey' do
      register = config.registry_for(type: :thumbnail)
      expect(register.applicable_for?(file_set: file_set)).to be_falsey
    end
  end

  describe '#register' do
    it 'amends the existing registry' do
      locator = double
      type = :thumbnail
      expect do
        config.register(type: type, locators: [locator], applicators: [])
      end.to change { config.registry_for(type: type).locators }.from([]).to([locator])
    end

    context 'validation' do
      it 'defaults to a truthy validator' do
        registry = config.register(type: :thumbnail, locators: [], applicators: [])
        expect(registry.applicable_for?(file_set: file_set)).to be_truthy
      end

      it 'allows for block configuration' do
        registry = config.register(type: :thumbnail, locators: [], applicators: []) do |_file_set|
          false
        end

        expect(registry.applicable_for?(file_set: file_set)).to be_falsey
      end
    end
  end
end
