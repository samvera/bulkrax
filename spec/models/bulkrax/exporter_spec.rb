# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe Exporter, type: :model do
    let(:exporter) { FactoryBot.create(:bulkrax_exporter) }
    let(:importer) { FactoryBot.create(:bulkrax_importer) }

    describe 'export_from' do
      it 'defines a list of export from types' do
        expect(exporter.export_from_list).to eq(
          [
            [I18n.t('bulkrax.exporter.labels.importer'), 'importer'],
            [I18n.t('bulkrax.exporter.labels.collection'), 'collection'],
            [I18n.t('bulkrax.exporter.labels.worktype'), 'worktype'],
            [I18n.t('bulkrax.exporter.labels.all'), 'all']
          ]
        )
      end
    end

    describe 'export_type' do
      it 'defines a list of export types' do
        expect(exporter.export_type_list).to eq(
          [
            [I18n.t('bulkrax.exporter.labels.metadata'), 'metadata'],
            [I18n.t('bulkrax.exporter.labels.full'), 'full']
          ]
        )
      end
    end

    describe 'export' do
      context 'from importer' do
        before do
          allow(Bulkrax::Importer).to receive(:find).with('1').and_return(importer)
        end

        it 'exports' do
          expect(exporter).to receive(:create_from_importer)
          exporter.export
        end
      end

      context 'from collection' do
        let(:exporter) { FactoryBot.create(:bulkrax_exporter_collection) }

        it 'exports' do
          expect(exporter).to receive(:create_from_collection)
          exporter.export
        end
      end

      context 'from worktype' do
        let(:exporter) { FactoryBot.create(:bulkrax_exporter_worktype) }

        it 'exports' do
          expect(exporter).to receive(:create_from_worktype)
          exporter.export
        end
      end
    end

    describe '#export_source accessors' do
      context 'when exporting from an importer' do
        it '#export_source_importer returns #export_source' do
          expect(exporter.export_source_importer).to eq(exporter.export_source)
        end

        it 'other #export_source accessors return nil' do
          expect(exporter.export_source_collection).to be_nil
          expect(exporter.export_source_worktype).to be_nil
        end
      end

      context 'when exporting from a collection' do
        let(:exporter) { FactoryBot.create(:bulkrax_exporter_collection) }

        it '#export_source_collection returns #export_source' do
          expect(exporter.export_source_collection).to eq(exporter.export_source)
        end

        it 'other #export_source accessors return nil' do
          expect(exporter.export_source_importer).to be_nil
          expect(exporter.export_source_worktype).to be_nil
        end
      end

      context 'when exporting from a worktype' do
        let(:exporter) { FactoryBot.create(:bulkrax_exporter_worktype) }

        it '#export_source_worktype returns #export_source' do
          expect(exporter.export_source_worktype).to eq(exporter.export_source)
        end

        it 'other #export_source accessors return nil' do
          expect(exporter.export_source_importer).to be_nil
          expect(exporter.export_source_collection).to be_nil
        end
      end
    end
  end
end
