# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe Importer, type: :model do
    let(:importer) do
      FactoryBot.create(:bulkrax_importer)
    end

    describe 'frequency' do
      it 'uses ISO 8601 for frequency' do
        importer.frequency = 'P1Y'
        expect(importer.frequency.to_seconds).to eq(31_536_000.0)
      end

      it 'uses ISO 8601 to determine schedulable' do
        importer.frequency = 'P1D'
        expect(importer.schedulable?).to eq(true)
      end
    end

    describe 'importer run' do
      before do
        allow_any_instance_of(Bulkrax::OaiDcParser).to receive(:collections_total).and_return(1)
      end

      it 'creates an ImporterRun with total_work_entries set to the value of limit' do
        importer.current_run
        expect(importer.current_run.total_work_entries).to eq(10)
        expect(importer.current_run.total_collection_entries).to eq(1)
      end
    end

    describe 'import works' do
      before do
        allow(Bulkrax::OaiDcParser).to receive(:new).and_return(Bulkrax::OaiDcParser.new(importer)) # .with(subject).and_return(parser)
        allow_any_instance_of(Bulkrax::OaiDcParser).to receive(:collections_total).and_return 5
        allow_any_instance_of(Bulkrax::OaiDcParser).to receive(:total).and_return 5
        allow_any_instance_of(Bulkrax::OaiDcParser).to receive(:create_collections)
        allow_any_instance_of(Bulkrax::OaiDcParser).to receive(:create_works)
      end

      it 'calls parser run' do
        importer.current_run
        importer.import_works
        expect(importer.only_updates).to eq(false)
      end
    end

    describe 'import outcome metrics' do
      include ActiveSupport::Testing::TimeHelpers

      let(:metrics_enabled) { true }
      let(:parser_fields) do
        { 'import_file_path' => 'spec/fixtures/csv/good.csv', 'guided_import' => true, 'metrics_session_id' => 'gi_test123' }
      end
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv, parser_fields: parser_fields) }
      let(:outcomes) { ImportMetric.import_outcomes }

      before { allow(Bulkrax.config).to receive(:guided_import_metrics_enabled).and_return(metrics_enabled) }

      context 'when a guided import run finishes' do
        it 'records the status the run finished with' do
          importer.record_status

          expect(outcomes.count).to eq(1)
          expect(outcomes.first).to have_attributes(
            importer_id: importer.id,
            importer_run_id: importer.current_run.id,
            session_id: 'gi_test123',
            outcome: 'Complete',
            first_attempt: true
          )
        end

        it 'keeps one row when the run is reported finished more than once' do
          2.times { importer.record_status }
          expect(outcomes.count).to eq(1)
        end

        it 'measures the duration from the start of the run to its last report' do
          importer.current_run
          travel(10.minutes) { importer.record_status }
          expect(outcomes.first.duration_ms).to be_within(5_000).of(600_000)
        end
      end

      context 'when the run still has records enqueued' do
        it 'records nothing' do
          importer.current_run.update!(enqueued_records: 1)
          importer.record_status
          expect(outcomes.count).to eq(0)
        end
      end

      context 'when a later run finishes differently' do
        it 'keeps the first run outcome as it was recorded' do
          importer.record_status
          first_run = importer.current_run

          importer.current_run = importer.importer_runs.create!
          importer.current_run.update!(failed_records: 1)
          importer.record_status

          expect(outcomes.find_by(importer_run: first_run)).to have_attributes(outcome: 'Complete', first_attempt: true)
          expect(outcomes.find_by(importer_run: importer.current_run)).to have_attributes(outcome: 'Complete (with failures)', first_attempt: false)
        end

        it 'still counts the first run as the first attempt when its last job reports after the re-run starts' do
          first_run = importer.current_run
          importer.importer_runs.create!

          importer.current_run = first_run
          importer.record_status

          expect(outcomes.find_by(importer_run: first_run).first_attempt).to eq(true)
        end
      end

      context 'when the parser fails while building entries' do
        it 'records the run as failed' do
          allow(importer.parser).to receive(:works).and_raise(StandardError, 'boom')
          importer.import_objects

          expect(outcomes.first).to have_attributes(importer_run_id: importer.current_run.id, outcome: 'Failed')
        end
      end

      context 'when a failure status is set on the importer' do
        it 'records the run as failed' do
          importer.set_status_info(CSV::MalformedCSVError.new('bad quote', 2))
          expect(outcomes.first).to have_attributes(importer_run_id: importer.current_run.id, outcome: 'Failed')
        end

        it 'records an earlier run as failed when the failure names that run' do
          first_run = importer.current_run
          importer.importer_runs.create!

          importer.set_status_info(StandardError.new('boom'), first_run)
          expect(outcomes.find_by(importer_run: first_run).outcome).to eq('Failed')
        end
      end

      context 'when a non-failure status is set outside record_status' do
        it 'records nothing' do
          importer.set_status_info('Complete')
          expect(outcomes.count).to eq(0)
        end
      end

      context 'when the importer is re-run from the edit form' do
        it 'keeps recording it as a guided import' do
          importer.update!(parser_fields: { 'import_file_path' => 'spec/fixtures/csv/good.csv', 'visibility' => 'open' })
          expect(importer.reload.parser_fields).to include('guided_import' => true, 'metrics_session_id' => 'gi_test123', 'visibility' => 'open')
        end
      end

      context 'when the metrics table has not been migrated' do
        let(:connection) { ActiveRecord::Base.connection }

        def hide_metrics_table(from, to)
          connection.rename_table(from, to)
          connection.schema_cache.clear!
          ImportMetric.reset_column_information
        end

        it 'still lets the importer be destroyed' do
          importer
          hide_metrics_table(:bulkrax_import_metrics, :bulkrax_import_metrics_hidden)
          expect { importer.destroy! }.not_to raise_error
        ensure
          hide_metrics_table(:bulkrax_import_metrics_hidden, :bulkrax_import_metrics)
        end
      end

      context 'when metrics are disabled' do
        let(:metrics_enabled) { false }

        it 'records nothing' do
          importer.record_status
          expect(outcomes.count).to eq(0)
        end
      end

      context 'when the importer was not created by the guided import' do
        let(:parser_fields) { { 'import_file_path' => 'spec/fixtures/csv/good.csv' } }

        it 'records nothing' do
          importer.record_status
          expect(outcomes.count).to eq(0)
        end
      end
    end

    describe 'field_mapping' do
      context 'oai_parser' do
        it 'retrieves the default field mapping for oai_dc' do
          expect(importer.mapping).to eq(
            "contributor" => { "excluded" => false, "from" => ["contributor"], "if" => nil, "parsed" => false, "split" => false },
            "coverage" => { "excluded" => false, "from" => ["coverage"], "if" => nil, "parsed" => false, "split" => false },
            "creator" => { "excluded" => false, "from" => ["creator"], "if" => nil, "parsed" => false, "split" => false },
            "date" => { "excluded" => false, "from" => ["date"], "if" => nil, "parsed" => false, "split" => false },
            "description" => { "excluded" => false, "from" => ["description"], "if" => nil, "parsed" => false, "split" => false },
            "format" => { "excluded" => false, "from" => ["format"], "if" => nil, "parsed" => false, "split" => false },
            "identifier" => { "excluded" => false, "from" => ["identifier"], "if" => nil, "parsed" => false, "split" => false },
            "language" => { "excluded" => false, "from" => ["language"], "if" => nil, "parsed" => true, "split" => false },
            "publisher" => { "excluded" => false, "from" => ["publisher"], "if" => nil, "parsed" => false, "split" => false },
            "relation" => { "excluded" => false, "from" => ["relation"], "if" => nil, "parsed" => false, "split" => false },
            "rights" => { "excluded" => false, "from" => ["rights"], "if" => nil, "parsed" => false, "split" => false },
            "source" => { "excluded" => false, "from" => ["source"], "if" => nil, "parsed" => false, "split" => false },
            "subject" => { "excluded" => false, "from" => ["subject"], "if" => nil, "parsed" => true, "split" => false },
            "title" => { "excluded" => false, "from" => ["title"], "if" => nil, "parsed" => false, "split" => false },
            "type" => { "excluded" => false, "from" => ["type"], "if" => nil, "parsed" => false, "split" => false }
          )
        end
      end
      context 'bulkrax_importer_csv' do
        let(:importer) do
          FactoryBot.create(:bulkrax_importer_csv, user: User.new(email: 'test@example.com'))
        end

        it 'creates a default mapping from the column headers' do
          expect(importer.mapping).to eq(
            "model" => { "excluded" => false, "from" => ["model"], "if" => nil, "parsed" => true, "split" => false },
            "parents_column" => { "excluded" => false, "from" => ["parents_column"], "if" => nil, "parsed" => false, "split" => false },
            "source_identifier" => { "excluded" => false, "from" => ["source_identifier"], "if" => nil, "parsed" => false, "split" => false },
            "title" => { "excluded" => false, "from" => ["title"], "if" => nil, "parsed" => false, "split" => false }
          )
        end
      end
    end

    describe '#zip?' do
      let(:importer) { described_class.new(parser_fields: { 'import_file_path' => path }) }

      subject { importer.zip? }

      context 'when the parser import_file_path is empty' do
        let(:path) { nil }
        it { is_expected.to be_falsey }
      end

      context 'when the parser import_file_path is for a csv' do
        let(:path) { 'spec/fixtures/csv/good.csv' }
        it { is_expected.to be_falsey }
      end

      context 'when the parser import_file_path is for a zip file' do
        let(:path) { 'spec/fixtures/zip/simple.zip' }
        it { is_expected.to be_truthy }
      end
    end

    # NOTE: the full contract for `#importer_unzip_path` lives in
    # spec/parsers/bulkrax/csv_parser/unzip_spec.rb alongside the CsvParser
    # extraction specs, where it can be exercised against real filesystem
    # behavior.

    describe '#original_files' do
      let(:csv_file) { Tempfile.new(['metadata', '.csv']) }
      let(:zip_file) { Tempfile.new(['attachments', '.zip']) }

      after do
        csv_file.close
        csv_file.unlink
        zip_file.close
        zip_file.unlink
      end

      context 'when only CSV file exists' do
        let(:importer) do
          FactoryBot.build(:bulkrax_importer_csv, parser_fields: { 'import_file_path' => csv_file.path })
        end

        it 'returns only the CSV file' do
          files = importer.original_files
          expect(files.size).to eq(1)
          expect(files.first[:type]).to eq(:csv)
          expect(files.first[:path]).to eq(csv_file.path)
          expect(files.first[:name]).to eq(File.basename(csv_file.path))
        end
      end

      context 'when both CSV and ZIP files exist' do
        let(:importer) do
          FactoryBot.build(:bulkrax_importer_csv, parser_fields: {
                             'import_file_path' => csv_file.path,
                             'attachments_zip_path' => zip_file.path
                           })
        end

        it 'returns both files in order' do
          files = importer.original_files
          expect(files.size).to eq(2)

          expect(files[0][:type]).to eq(:csv)
          expect(files[0][:path]).to eq(csv_file.path)
          expect(files[0][:name]).to eq(File.basename(csv_file.path))

          expect(files[1][:type]).to eq(:zip)
          expect(files[1][:path]).to eq(zip_file.path)
          expect(files[1][:name]).to eq(File.basename(zip_file.path))
        end
      end

      context 'when no files exist' do
        let(:importer) { FactoryBot.build(:bulkrax_importer_csv, parser_fields: {}) }

        it 'returns an empty array' do
          expect(importer.original_files).to eq([])
        end
      end

      context 'when files are specified but do not exist on disk' do
        let(:importer) do
          FactoryBot.build(:bulkrax_importer_csv, parser_fields: {
                             'import_file_path' => '/nonexistent/file.csv',
                             'attachments_zip_path' => '/nonexistent/file.zip'
                           })
        end

        it 'returns an empty array' do
          expect(importer.original_files).to eq([])
        end
      end
    end
  end
end
