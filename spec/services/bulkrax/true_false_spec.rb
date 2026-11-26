# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::TrueFalse do
  describe '.cast' do
    ['true', 'TRUE', 'True', 't', 'T', 'yes', 'Yes', 'y', 'on', 'On', '1', ' true ', true].each do |value|
      it "reads #{value.inspect} as true" do
        expect(described_class.cast(value)).to be true
      end
    end

    ['false', 'FALSE', 'False', 'f', 'no', 'No', 'n', 'off', 'Off', '0', ' false', '', nil, false].each do |value|
      it "reads #{value.inspect} as false" do
        expect(described_class.cast(value)).to be false
      end
    end

    ['maybe', '2', 'nope'].each do |value|
      it "reads #{value.inspect} as neither" do
        expect(described_class.cast(value)).to be_nil
      end
    end
  end
end
