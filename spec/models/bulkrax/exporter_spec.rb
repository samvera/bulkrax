# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe Exporter, type: :model do
    let(:exporter) { FactoryBot.create(:bulkrax_exporter, limit: 7) }
    let(:importer) { FactoryBot.create(:bulkrax_importer) }

    describe 'export_from' do
      # rubocop:disable RSpec/ExampleLength
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
      # rubocop:enable RSpec/ExampleLength
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

      context '#current_run' do
        it 'sets @current_run' do
          expect(exporter.instance_variable_get(:@current_run)).to be_nil

          exporter.current_run

          expect(exporter.instance_variable_get(:@current_run)).not_to be_nil
          expect(exporter.current_run.enqueued_records).to eq(7)
          expect(exporter.current_run.total_work_entries).to eq(7)
          expect(exporter.current_run.exporter_id).to eq(exporter.id)
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

    context '#exporter_export_zip_path' do
      describe 'without an exporter run' do
        it 'returns a path to the exported zip files' do
          expect(exporter.exporter_export_zip_path).to eq('tmp/exports/export_1_0')
        end
      end

      describe 'with an exporter run' do
        let(:bulkrax_exporter_run) { FactoryBot.create(:bulkrax_exporter_run, exporter: exporter) }

        before do
          allow(exporter).to receive(:exporter_runs).and_return([bulkrax_exporter_run])
        end

        it 'returns a path to the exported zip files' do
          expect(exporter.exporter_export_zip_path).to eq('tmp/exports/export_1_1')
        end
      end
    end

    describe '#sort_zip_files' do
      it 'orders the zip files numerically' do
        zip_files = ['export_1_10.zip', 'export_1_2.zip']
        sorted = exporter.sort_zip_files(zip_files)

        expect(sorted[0]).to eq('export_1_2.zip')
        expect(sorted[1]).to eq('export_1_10.zip')
      end
    end
  end
end
