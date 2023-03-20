# frozen_string_literal: true
require 'rails_helper'
require 'samvera/derivatives'
require 'samvera/derivatives/hyrax'

RSpec.describe Samvera::Derivatives::Hyrax::ServiceShim do
  let(:config) { Samvera::Derivatives::Configuration.new }
  let(:file_set) { FileSet.new }
  let(:other_locator) { double('Locator', locate: nil) }
  let(:other_applicator) { double('Applicator', apply!: nil) }
  before do
    config.register(
      type: :thumbnail,
      locators: [other_locator, Samvera::Derivatives::Hyrax::FileLocatorStrategy],
      applicators: [other_applicator, Samvera::Derivatives::Hyrax::FileApplicatorStrategy]
    ) { |_file_set| true }
    config.register(
      type: :jpg,
      locators: [other_locator, Samvera::Derivatives::Hyrax::FileLocatorStrategy],
      applicators: [other_applicator, Samvera::Derivatives::Hyrax::FileApplicatorStrategy]
    ) { |_file_set| true }
  end

  let(:shim) { described_class.new(file_set, candidate_derivative_types: [:thumnail, :jpg], config: config) }

  subject { shim }

  it { is_expected.to be_valid }

  describe '#create_derivatives' do
    let(:file_path) { __FILE__ }
    subject { shim.create_derivatives(file_path) }

    context 'when other locator and applicator are not applicable' do
      it 'locates and applies the derivatives using the underlying service' do
        expect_any_instance_of(Samvera::Derivatives::Hyrax::FileApplicatorStrategy).to receive(:apply!).and_call_original
        expect_any_instance_of(Samvera::Derivatives::Hyrax::FileSetDerivativesServiceWrapper).to receive(:apply!).and_call_original
        expect_any_instance_of(::Hyrax::FileSetDerivativesService).to receive(:valid?).and_return(true)
        expect_any_instance_of(::Hyrax::FileSetDerivativesService).to receive(:create_derivatives).with(file_path)
        expect(other_applicator).to receive(:apply!)

        subject
      end
    end

    context 'when the other locator finds the derivative' do
      let(:other_locator) { double(locate: file_path) }

      it 'uses that located derivative and applies it' do
        # Yes, we will attempt to apply the derivative...
        expect_any_instance_of(Samvera::Derivatives::Hyrax::FileApplicatorStrategy).to receive(:apply!).and_call_original
        # ...however, we won't be leveraging the wrapper's derivative work; meaning no default behavior.
        expect_any_instance_of(Samvera::Derivatives::Hyrax::FileSetDerivativesServiceWrapper).not_to receive(:apply!)
        expect_any_instance_of(::Hyrax::FileSetDerivativesService).not_to receive(:valid?)
        expect_any_instance_of(::Hyrax::FileSetDerivativesService).not_to receive(:create_derivatives)
        expect(other_applicator).to receive(:apply!)

        subject
      end
    end
  end
end
