# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe 'Exporting from Bagit' do
    let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }
    let(:exporter) { FactoryBot.create(:bulkrax_exporter, parser_klass: 'Bulkrax::BagitParser', export_from: 'all') }
    let(:bulkrax_exporter_run) { FactoryBot.create(:bulkrax_exporter_run, exporter: exporter) }
    before do
      stub_request(:head, %r{http://localhost:8986/rest/test.*}).to_return(status: 200, body: "", headers: {})
      stub_request(:get, %r{http://localhost:8986/rest/test.*}).to_return(status: 200, body: "", headers: {})
      importer.import_works
      allow(exporter.parser).to receive(:current_records_for_export)
        .and_return(importer.entries.map { |e| [e.identifier, e.class] })
    end

    it 'exports a work' do
      ActiveJob::Base.queue_adapter = :test

      # rubocop:disable Style/BlockDelimiters
      expect {
        ExportWorkJob.perform_later
      }.to have_enqueued_job(ExportWorkJob)
      # rubocop:enable Style/BlockDelimiters

      exporter.export
    end
  end
end
