# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe Exporter, type: :model do
    let(:exporter) { FactoryBot.create(:bulkrax_exporter) }
    let(:importer) { FactoryBot.create(:bulkrax_importer) }

    describe 'export_from' do
      it 'defines a list of export from types' do
        expect(exporter.export_from_list).to eq([
          [I18n.t('bulkrax.exporter.labels.collection'), 'collection'],
          [I18n.t('bulkrax.exporter.labels.importer'), 'importer'],
          [I18n.t('bulkrax.exporter.labels.worktype'), 'worktype']
        ])
      end
    end

    describe 'export_type' do
      it 'defines a list of export types' do
        expect(exporter.export_type_list).to eq([
          [I18n.t('bulkrax.exporter.labels.metadata'), 'metadata'],
          [I18n.t('bulkrax.exporter.labels.full'), 'full']
        ])
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
  end
end
