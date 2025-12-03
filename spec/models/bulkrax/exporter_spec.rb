# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe Exporter, type: :model do
    let(:exporter) { FactoryBot.create(:bulkrax_exporter, limit: 7) }
    let(:importer) { FactoryBot.create(:bulkrax_importer) }
    let(:user) { create(:base_user) }

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

    describe '#exporter_export_zip_path' do
      context 'without an exporter run' do
        it 'returns a path to the exported zip files' do
          expect(exporter.exporter_export_zip_path).to eq("tmp/exports/export_#{exporter.id}_0")
        end
      end

      describe 'with an exporter run' do
        let(:bulkrax_exporter_run) { FactoryBot.create(:bulkrax_exporter_run, exporter: exporter) }

        before do
          allow(exporter).to receive(:exporter_runs).and_return([bulkrax_exporter_run])
        end

        it 'returns a path to the exported zip files' do
          expect(exporter.exporter_export_zip_path).to eq("tmp/exports/export_#{exporter.id}_#{bulkrax_exporter_run.id}")
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

    describe 'CSV export configuration' do
      context 'with all_records export_from' do
        context 'metadata_only export' do
          let(:exporter) do
            create(:bulkrax_exporter, :all,
                  name: 'CSV Export Test - Metadata Only',
                  user: user,
                  export_type: 'metadata',
                  parser_fields: {
                    'export_from' => 'all',
                    'metadata_only' => true
                  })
          end

          it 'configures for metadata only export' do
            expect(exporter.export_type).to eq('metadata')
            expect(exporter.parser_fields['metadata_only']).to be true
            expect(exporter.export_from).to eq('all')
          end

          it 'uses CSV parser by default' do
            expect(exporter.parser_klass).to eq('Bulkrax::CsvParser')
          end
        end

        context 'metadata + files export' do
          let(:exporter) do
            create(:bulkrax_exporter, :all,
                  name: 'CSV Export Test - Metadata and Files',
                  user: user,
                  export_type: 'full',
                  parser_fields: {
                    'export_from' => 'all',
                    'include_files' => true
                  })
          end

          it 'configures for full export with files' do
            expect(exporter.export_type).to eq('full')
            expect(exporter.parser_fields['include_files']).to be true
            expect(exporter.export_from).to eq('all')
          end
        end

        context 'include generated metadata' do
          let(:exporter) do
            create(:bulkrax_exporter, :all,
                  name: 'CSV Export Test - Generated Metadata',
                  user: user,
                  generated_metadata: true,
                  parser_fields: {
                    'export_from' => 'all',
                    'include_generated_metadata' => true
                  })
          end

          it 'configures to include system-generated fields' do
            expect(exporter.generated_metadata).to be true
            expect(exporter.parser_fields['include_generated_metadata']).to be true
          end
        end

        context 'include thumbnails' do
          let(:exporter) do
            create(:bulkrax_exporter, :all,
                  name: 'CSV Export Test - Include Thumbnails',
                  user: user,
                  include_thumbnails: true,
                  parser_fields: {
                    'export_from' => 'all',
                    'include_thumbnails' => true
                  })
          end

          it 'configures to include thumbnails' do
            expect(exporter.include_thumbnails).to be true
            expect(exporter.parser_fields['include_thumbnails']).to be true
          end
        end

        context 'visibility filter' do
          context 'open visibility only' do
            let(:exporter) do
              create(:bulkrax_exporter, :all,
                    name: 'CSV Export Test - Open Only',
                    user: user,
                    work_visibility: 'open',
                    parser_fields: {
                      'export_from' => 'all',
                      'visibility_filter' => 'open'
                    })
            end

            it 'configures visibility filter correctly' do
              expect(exporter.work_visibility).to eq('open')
              expect(exporter.parser_fields['visibility_filter']).to eq('open')
            end
          end

          context 'restricted visibility only' do
            let(:exporter) do
              create(:bulkrax_exporter, :all,
                    name: 'CSV Export Test - Restricted Only',
                    user: user,
                    work_visibility: 'restricted',
                    parser_fields: {
                      'export_from' => 'all',
                      'visibility_filter' => 'restricted'
                    })
            end

            it 'configures for restricted visibility only' do
              expect(exporter.work_visibility).to eq('restricted')
              expect(exporter.parser_fields['visibility_filter']).to eq('restricted')
            end
          end
        end

        context 'date filter' do
          context 'date range filter' do
            let(:exporter) do
              create(:bulkrax_exporter, :all,
                    name: 'CSV Export Test - Date Range',
                    user: user,
                    start_date: 6.months.ago.to_date,
                    finish_date: Date.current,
                    parser_fields: {
                      'export_from' => 'all',
                      'start_date' => 6.months.ago.to_date.to_s,
                      'finish_date' => Date.current.to_s
                    })
            end

            it 'configures date range filter correctly' do
              expect(exporter.start_date).to eq(6.months.ago.to_date)
              expect(exporter.finish_date).to eq(Date.current)
              expect(exporter.parser_fields['start_date']).to eq(6.months.ago.to_date.to_s)
              expect(exporter.parser_fields['finish_date']).to eq(Date.current.to_s)
            end
          end

          context 'start date only' do
            let(:exporter) do
              create(:bulkrax_exporter, :all,
                    name: 'CSV Export Test - Start Date',
                    user: user,
                    start_date: 6.months.ago.to_date,
                    parser_fields: {
                      'export_from' => 'all',
                      'start_date' => 6.months.ago.to_date.to_s
                    })
            end

            it 'configures start date filter correctly' do
              expect(exporter.start_date).to eq(6.months.ago.to_date)
              expect(exporter.parser_fields['start_date']).to eq(6.months.ago.to_date.to_s)
            end
          end
        end

        context 'status filter' do
          context 'workflow status filter' do
            let(:exporter) do
              create(:bulkrax_exporter, :all,
                    name: 'CSV Export Test - Status Filter',
                    user: user,
                    workflow_status: 'deposited',
                    parser_fields: {
                      'export_from' => 'all',
                      'workflow_status_filter' => 'deposited'
                    })
            end

            it 'configures workflow status filter correctly' do
              expect(exporter.workflow_status).to eq('deposited')
              expect(exporter.parser_fields['workflow_status_filter']).to eq('deposited')
            end
          end
        end

        context 'combined filters' do
          let(:exporter) do
            create(:bulkrax_exporter, :all,
                  name: 'CSV Export Test - Combined Filters',
                  user: user,
                  work_visibility: 'open',
                  start_date: 6.months.ago.to_date,
                  workflow_status: 'deposited',
                  parser_fields: {
                    'export_from' => 'all',
                    'visibility_filter' => 'open',
                    'start_date' => 6.months.ago.to_date.to_s,
                    'workflow_status_filter' => 'deposited'
                  })
          end

          it 'configures multiple filters simultaneously' do
            expect(exporter.work_visibility).to eq('open')
            expect(exporter.start_date).to eq(6.months.ago.to_date)
            expect(exporter.workflow_status).to eq('deposited')
            expect(exporter.parser_fields['visibility_filter']).to eq('open')
            expect(exporter.parser_fields['start_date']).to eq(6.months.ago.to_date.to_s)
            expect(exporter.parser_fields['workflow_status_filter']).to eq('deposited')
          end
        end
      end
    end

    describe 'export status and lifecycle' do
      let(:exporter) { create(:bulkrax_exporter, :all, user: user, name: 'Status Test Exporter') }

      it 'has initial pending status' do
        expect(exporter.status_message).to eq('Pending')
      end

      it 'tracks export timestamps' do
        expect(exporter.last_error_at).to be_nil
        expect(exporter.last_succeeded_at).to be_nil
      end

      it 'can store error information' do
        exporter.update(error_class: 'StandardError', status_message: 'Export failed')

        expect(exporter.error_class).to eq('StandardError')
        expect(exporter.status_message).to eq('Export failed')
      end
    end

    describe 'associations and validations' do
      let(:exporter) { create(:bulkrax_exporter, :all, user: user) }

      it 'belongs to a user' do
        expect(exporter.user).to eq(user)
        expect(exporter.user).to be_a(User)
      end

      it 'has a name' do
        expect(exporter.name).to be_present
      end

      it 'has parser configuration' do
        expect(exporter.parser_klass).to eq('Bulkrax::CsvParser')
        expect(exporter.parser_fields).to be_a(Hash)
      end

      it 'validates presence of required fields' do
        invalid_exporter = build(:bulkrax_exporter, name: nil, user: user)
        expect(invalid_exporter).not_to be_valid
        expect(invalid_exporter.errors[:name]).to include("can't be blank")
      end
    end

    describe 'parser field management' do
      let(:exporter) { create(:bulkrax_exporter, :all, user: user) }

      it 'stores parser_fields as JSON' do
        exporter.parser_fields = { 'custom_field' => 'custom_value' }
        exporter.save!

        exporter.reload
        expect(exporter.parser_fields['custom_field']).to eq('custom_value')
      end

      it 'handles nil parser_fields gracefully' do
        exporter.parser_fields = nil
        exporter.save!

        exporter.reload
        expect(exporter.parser_fields).to be_nil
      end
    end
  end
end
