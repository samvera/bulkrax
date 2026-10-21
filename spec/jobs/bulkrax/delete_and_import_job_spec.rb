# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe DeleteAndImportJob, type: :job do
    let(:importer_run) { create(:bulkrax_importer_run, enqueued_records: 2) }
    let(:entry) { create(:bulkrax_csv_entry, importerexporter: importer_run.importer) }

    before do
      allow(entry).to receive(:factory).and_return(instance_double(ObjectFactory, delete: true, find: nil))
      allow_any_instance_of(Entry).to receive(:build) { |built| built.set_status_info('Complete') }
    end

    shared_examples 'a rerun that counts the record once' do |processed_type_counter|
      it 'counts the record as finished once' do
        described_class.perform_now(entry, importer_run)

        expect(importer_run.reload)
          .to have_attributes(enqueued_records: 1, processed_records: 1, processed_type_counter => 1)
      end
    end

    shared_examples 'a rerun that waits for relationships' do
      it 'shows the entry as Pending while it re-imports, so relationships wait for it' do
        status_during_import = nil
        allow_any_instance_of(Entry).to receive(:build) do |built|
          status_during_import = Entry.find(built.id).status_message
          built.set_status_info('Complete')
        end

        described_class.perform_now(entry, importer_run)

        expect(status_during_import).to eq('Pending')
      end
    end

    describe DeleteAndImportWorkJob do
      it_behaves_like 'a rerun that counts the record once', :processed_works
      it_behaves_like 'a rerun that waits for relationships'
    end

    describe DeleteAndImportCollectionJob do
      it_behaves_like 'a rerun that counts the record once', :processed_collections
      it_behaves_like 'a rerun that waits for relationships'
    end

    describe DeleteAndImportFileSetJob do
      it_behaves_like 'a rerun that counts the record once', :processed_file_sets
      it_behaves_like 'a rerun that waits for relationships'
    end
  end
end
