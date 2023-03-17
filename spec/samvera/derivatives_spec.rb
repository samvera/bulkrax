# frozen_string_literal: true
require 'rails_helper'
require 'samvera/derivatives'

RSpec.describe Samvera::Derivatives do
  describe '.config' do
    subject { described_class.config }

    it { is_expected.to be_a(described_class::Configuration) }
  end

  describe '.locate_and_apply_derivative_for' do
    let(:file_set) { double(FileSet) }
    let(:file_path) { __FILE__ }
    let(:applicability) { true }
    let(:type) { :thumbnail }
    let(:locator) { described_class::FileLocator::Strategy }
    let(:applicator) { described_class::FileApplicator::Strategy }

    let(:derivative) do
      described_class::Configuration::RegisteredType.new(
        type: type,
        applicators: [applicator],
        locators: [locator],
        applicability: ->(_) { applicability }
      )
    end

    subject do
      described_class.locate_and_apply_derivative_for(
        file_set: file_set,
        derivative: derivative,
        file_path: file_path
      )
    end

    context 'when not applicable' do
      let(:applicability) { false }

      it { is_expected.to be_falsey }
    end

    context 'when applicable' do
      let(:from_location) { :from_location }

      it 'locates then applies the derivative' do
        expect(locator).to receive(:locate).and_return(from_location)
        expect(applicator).to receive(:apply!).with(file_set: file_set, derivative_type: type, from_location: from_location)

        subject
      end
    end
  end
end
