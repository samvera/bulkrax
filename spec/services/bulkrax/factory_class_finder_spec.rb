# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::FactoryClassFinder do
  let(:legacy_work_class) { Class.new }
  let(:legacy_work_resource_class) { Class.new }
  let(:valkyrie_only_resource_class) { Class.new }
  let(:active_fedora_only_class) { Class.new }

  before do
    Object.const_set(:LegacyWork, legacy_work_class)
    Object.const_set(:LegacyWorkResource, legacy_work_resource_class)
    Object.const_set(:ValkyrieOnlyResource, valkyrie_only_resource_class)
    Object.const_set(:ActiveFedoraOnly, active_fedora_only_class)
  end

  after do
    Object.send(:remove_const, :LegacyWork)
    Object.send(:remove_const, :LegacyWorkResource)
    Object.send(:remove_const, :ValkyrieOnlyResource)
    Object.send(:remove_const, :ActiveFedoraOnly)
  end

  describe "DefaultCoercer" do
    it "simply constantizes (unsafely) the given string" do
      factory_class_name = "Work"
      expect(described_class::DefaultCoercer.call(factory_class_name)).to eq(Work)
    end
  end

  describe "ValkyrieMigrationCoercer" do
    it 'favors mapping names to those ending in Resource' do
      expect(described_class::ValkyrieMigrationCoercer.call("LegacyWork")).to eq(legacy_work_resource_class)
      expect(described_class::ValkyrieMigrationCoercer.call("LegacyWorkResource")).to eq(legacy_work_resource_class)
      expect(described_class::ValkyrieMigrationCoercer.call("ValkyrieOnlyResource")).to eq(valkyrie_only_resource_class)
      expect(described_class::ValkyrieMigrationCoercer.call("ValkyrieOnly")).to eq(valkyrie_only_resource_class)
      expect(described_class::ValkyrieMigrationCoercer.call("ActiveFedoraOnly")).to eq(active_fedora_only_class)
      expect { described_class::ValkyrieMigrationCoercer.call("ActiveFedoraOnlyResource") }.to raise_error(NameError)
    end
  end

  describe '.find' do
    let(:entry) { double(Bulkrax::Entry, parsed_metadata: { "model" => model_name }, default_work_type: "Work") }
    subject(:finder) { described_class.find(entry: entry, coercer: coercer) }

    [
      [Bulkrax::FactoryClassFinder::DefaultCoercer, "Legacy Work", "LegacyWork"],
      [Bulkrax::FactoryClassFinder::ValkyrieMigrationCoercer, "Legacy Work", "LegacyWorkResource"],
      [Bulkrax::FactoryClassFinder::DefaultCoercer, "Legacy Work Resource", "LegacyWorkResource"]
    ].each do |given_coercer, given_model_name, expected_class_name|
      context "with an entry with model: #{given_model_name} and coercer: #{given_coercer}" do
        let(:model_name) { given_model_name }
        let(:coercer) { given_coercer }

        it { is_expected.to eq expected_class_name.constantize }
      end
    end
  end
end
