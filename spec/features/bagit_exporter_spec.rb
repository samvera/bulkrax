# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe 'Exporting from Bagit' do
    let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }
    let(:exporter) { FactoryBot.create(:bulkrax_exporter, parser_klass: 'Bulkrax::BagitParser', export_from: 'all') }
    let(:bulkrax_exporter_run) { FactoryBot.create(:bulkrax_exporter_run, exporter: exporter) }
    before do
      importer.impxort_works
      allow(exporter.parser).to receive(:current_record_ids).and_return(importer.entries.pluck(:identifier))
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
