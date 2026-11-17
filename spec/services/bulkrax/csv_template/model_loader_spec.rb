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

    context 'when a model name cannot be constantized' do
      it 'omits the invalid model and keeps the valid ones' do
        loader = described_class.new(['GenericWork', 'NonExistentModel'])
        expect(loader.models).to include('GenericWork')
        expect(loader.models).not_to include('NonExistentModel')
      end
    end
  end

  describe '.determine_klass_for' do
    before { allow(described_class).to receive(:determine_klass_for).and_call_original }

    it 'returns GenericWork for GenericWork' do
      expect(described_class.determine_klass_for('GenericWork')).to eq(GenericWork)
    end

    it 'returns nil for a model name with no class' do
      expect(described_class.determine_klass_for('NoSuchModel')).to be_nil
    end

    it 'returns file_model_class FileSet for hyrax::fileset' do
      expect(described_class.determine_klass_for('hyrax::fileset')).to eq(Bulkrax.file_model_class)
    end

    it 'returns collection_model_class Collection for CollectionResource' do
      stub_const('CollectionResource', Class.new)

      expect(described_class.determine_klass_for('CollectionResource')).to eq(Bulkrax.collection_model_class)
    end

    context 'when factory_class_name_coercer turns Image into ImageResource' do
      before do
        stub_const('Image', Class.new)
        stub_const('ImageResource', Class.new)
        allow(Bulkrax).to receive(:factory_class_name_coercer).and_return(Bulkrax::FactoryClassFinder::ValkyrieMigrationCoercer)
      end

      it 'returns ImageResource for Image, the class the importer creates' do
        expect(described_class.determine_klass_for('Image')).to eq(ImageResource)
      end
    end
  end
end
