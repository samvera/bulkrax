# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvTemplate::ModelLoader do
  before { stub_bulkrax_models }

  describe '#initialize / #models' do
    context 'when an explicit list of model names is given' do
      it 'returns the given model names' do
        loader = described_class.new(['GenericWork'])
        expect(loader.models).to eq(['GenericWork'])
      end

      it 'returns multiple model names' do
        loader = described_class.new(['GenericWork', 'Collection'])
        expect(loader.models).to eq(['GenericWork', 'Collection'])
      end
    end

    context 'when the list is empty' do
      it 'falls back to all available models' do
        loader = described_class.new([])
        expect(loader.models).to include('GenericWork', 'Collection', 'FileSet')
      end
    end

    context "when the list contains 'all'" do
      it 'loads all available models' do
        loader = described_class.new(['all'])
        expect(loader.models).to include('GenericWork', 'Collection', 'FileSet')
      end
    end

    context 'when given a non-Array value' do
      it 'falls back to all available models' do
        loader = described_class.new(nil)
        expect(loader.models).to include('GenericWork', 'Collection', 'FileSet')
      end
    end

    context 'when a model name cannot be constantized' do
      it 'omits the invalid model and keeps the valid ones' do
        loader = described_class.new(['GenericWork', 'NonExistentModel'])
        expect(loader.models).to include('GenericWork')
        expect(loader.models).not_to include('NonExistentModel')
      end
    end
  end

  describe '.determine_klass_for' do
    context 'when using ActiveFedora object factory' do
      before do
        allow(Bulkrax.config).to receive(:object_factory).and_return(double)
      end

      it 'returns the class for a known model name' do
        expect(described_class.determine_klass_for('GenericWork')).to eq(GenericWork)
      end

      it 'returns nil for an unknown model name' do
        expect(described_class.determine_klass_for('NoSuchModel')).to be_nil
      end
    end

    context 'when using ValkyrieObjectFactory' do
      let(:resolver) { ->(_name) { GenericWork } }

      before do
        allow(Bulkrax.config).to receive(:object_factory).and_return(Bulkrax::ValkyrieObjectFactory)
        allow(Valkyrie.config).to receive(:resource_class_resolver).and_return(resolver)
      end

      it 'uses the resource_class_resolver' do
        expect(described_class.determine_klass_for('GenericWork')).to eq(GenericWork)
      end
    end
  end
end
