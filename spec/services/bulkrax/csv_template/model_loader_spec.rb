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

    context 'when factory_class_name_coercer turns Image into ImageResource and there is no Image class' do
      before do
        stub_const('ImageResource', Class.new)
        allow(Bulkrax).to receive(:factory_class_name_coercer).and_return(Bulkrax::FactoryClassFinder::ValkyrieMigrationCoercer)
      end

      it 'keeps Image, since the importer creates an ImageResource for it' do
        expect(described_class.new(['Image']).models).to eq(['Image'])
      end
    end

    context 'when factory_class_name_coercer raises something other than NameError' do
      before do
        allow(Bulkrax).to receive(:factory_class_name_coercer).and_return(->(_name) { raise ArgumentError, 'broken coercer' })
      end

      it 'raises it instead of returning no models' do
        expect { described_class.new(['Image']) }.to raise_error(ArgumentError, 'broken coercer')
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
    it 'warns that it is deprecated in favor of FactoryClassFinder.resolve' do
      expect(Deprecation).to receive(:warn).with(described_class, /Bulkrax::FactoryClassFinder\.resolve/)

      described_class.determine_klass_for('GenericWork')
    end

    it 'returns what FactoryClassFinder.resolve returns' do
      allow(Deprecation).to receive(:warn)

      expect(described_class.determine_klass_for('hyrax::fileset')).to eq(Bulkrax::FactoryClassFinder.resolve('hyrax::fileset'))
    end
  end
end
