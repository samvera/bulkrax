# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe Status, type: :model do
    context 'for exporters' do
      let(:exporter_without_errors) { FactoryBot.create(:bulkrax_exporter) }
      let(:exporter_with_errors) { Bulkrax::Exporter.new }
      context 'when there are no errors' do
        it 'can display the current status' do
          exporter_without_errors.save
          expect(exporter_without_errors.statuses.count).to eq 0
          expect(exporter_without_errors.last_error_at).to eq nil
          expect(exporter_without_errors.error_class).to eq nil
          expect(exporter_without_errors.status).to eq 'Pending'
        end
      end
      context 'when there are errors' do
        it 'can display a history' do
        end
      end
    end
    context 'for importers' do
      let(:importer_without_errors) { FactoryBot.create(:bulkrax_importer) }
      let(:importer_with_errors) { Bulkrax::Importer.new }

      context 'when there are no errors' do
        it 'can display the current status' do
          importer_without_errors.save
          expect(importer_without_errors.statuses.count).to eq 0
          expect(importer_without_errors.last_error_at).to eq nil
          expect(importer_without_errors.error_class).to eq nil
          expect(importer_without_errors.status).to eq 'Pending'
        end
      end
      context 'when there are errors' do

        before do
          allow_any_instance_of(AdminSet).to receive(:update_index).and_return(true)
        end

        it 'can display a history' do
          expect { importer_with_errors.import_objects }.to raise_error(StandardError)
          importer_with_errors.import_objects
          expect(importer_with_errors.statuses.count).to eq 1
          expect(importer_with_errors.status_message).to eq 'Failed'
          expect(importer_with_errors.statuses[0].status_message).to eq 'Failed'
          expect(importer_with_errors.statuses[0].error_message).to eq 'Missing required elements, missing element(s) are: title'
          expect(importer_with_errors.statuses[0].error_backtrace.nil?).to eq false
          expect(importer_with_errors.error_class).to eq 'StandardError'
          expect { importer_with_errors.import_objects }.to raise_error(StandardError)
          expect(importer_with_errors.statuses.count).to eq 2
        end
      end
    end
    context 'for csv entries' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }
      let(:entry_without_errors) { FactoryBot.create(:bulkrax_csv_entry) }
      let(:entry_with_errors) { Bulkrax::CsvEntry.new(importerexporter: importer) }
      let(:collection) { FactoryBot.build(:collection) }
      let(:hyrax_record) do
        OpenStruct.new(
          file_sets: [],
          member_of_collections: [],
          member_of_work_ids: [],
          in_work_ids: [],
          member_work_ids: []
        )
      end

      before do
        allow(entry_with_errors).to receive(:hyrax_record).and_return(hyrax_record)
      end

      context 'when there are no errors' do
        it 'can display the current status' do
          entry_without_errors.save
          expect(entry_without_errors.statuses.count).to eq 0
          expect(entry_without_errors.last_error_at).to eq nil
          expect(entry_without_errors.error_class).to eq nil
          expect(entry_without_errors.status).to eq 'Pending'
        end
      end
      context 'when there are errors' do
        context 'for missing metadata' do
          before do
            allow_any_instance_of(Bulkrax::CsvEntry).to receive(:collections_created?).and_return(true)
            allow_any_instance_of(Bulkrax::CsvEntry).to receive(:find_collection).and_return(collection)
            allow(entry_with_errors).to receive(:raw_metadata).and_return(source_identifier: '1', some_field: 'some data')
          end
          it 'can display a history' do
            expect { entry_with_errors.build_metadata }.to raise_error(StandardError)
            expect(entry_with_errors.statuses.count).to eq 1
            expect(entry_with_errors.status_message).to eq 'Failed'
            expect(entry_with_errors.statuses[0].status_message).to eq 'Failed'
            expect(entry_with_errors.statuses[0].error_message).to eq 'Missing required elements, missing element(s) are: title'
            expect(entry_with_errors.statuses[0].error_backtrace.nil?).to eq false
            expect(entry_with_errors.error_class).to eq 'StandardError'
            expect { entry_with_errors.build_metadata }.to raise_error(StandardError)
            expect(entry_with_errors.statuses.count).to eq 2
          end
        end

        context 'for missing collection' do
          before do
            allow_any_instance_of(Bulkrax::CsvEntry).to receive(:collections_created?).and_return(false)
            allow_any_instance_of(Bulkrax::CsvEntry).to receive(:find_collection).and_return(nil)
            allow(entry_with_errors).to receive(:raw_metadata).and_return(source_identifier: '1', some_field: 'some data', title: 'Missing Collection Example')
          end
          it 'can display a history' do
            expect { entry_with_errors.build_metadata }.to raise_error(RuntimeError, /Metadata failed to build/)
            expect(entry_with_errors.statuses.count).to eq 1
            expect(entry_with_errors.status_message).to eq 'Failed'
            expect(entry_with_errors.statuses[0].status_message).to eq 'Failed'
            expect(entry_with_errors.statuses[0].error_message).to eq 'Missing required elements, missing element(s) are: title'
            expect(entry_with_errors.statuses[0].error_backtrace.nil?).to eq false
            expect(entry_with_errors.error_class).to eq 'StandardError'
            expect { entry_with_errors.build_metadata }.to raise_error(StandardError)
            expect(entry_with_errors.statuses.count).to eq 2
          end
        end
      end
    end
  end
end
