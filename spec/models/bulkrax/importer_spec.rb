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

    describe '#increment_counters' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }
      let(:run) { importer.current_run }

      before do
        run.update!(enqueued_records: 1)
        allow(ImporterRun).to receive(:find).and_wrap_original do |original, *args|
          original.call(*args).tap { ImporterRun.decrement_counter(:enqueued_records, run.id) } # rubocop:disable Rails/SkipsModelValidations
        end
      end

      it 'keeps a decrement from a job that finishes while the count is being saved' do
        importer.increment_counters(0, work: true)

        expect(run.reload.enqueued_records).to eq(1)
      end
    end

    describe '#import_objects' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }
      let(:deferred_work_jobs) { [] }

      before do
        allow(importer.parser).to receive(:collections).and_return([{ source_identifier: 'col_1', model: 'Collection' }])
        allow(importer.parser).to receive(:works).and_return([{ source_identifier: 'work_1' }])
        allow_any_instance_of(CsvEntry).to receive(:build) { |entry| entry.set_status_info('Complete') }
        allow(ImportCollectionJob).to receive(:perform_later) { |*args| ImportCollectionJob.perform_now(*args) }
      end

      context 'when a job finishes before the parser has enqueued every record' do
        before do
          allow(ImportWorkJob).to receive(:perform_later) { |*args| deferred_work_jobs << args }
        end

        it 'leaves the importer pending until the remaining jobs finish' do
          importer.import_objects(%w[collection work])

          expect(importer.reload.status).to eq('Pending')
        end

        it 'marks the importer complete when the last job finishes' do
          importer.import_objects(%w[collection work])
          deferred_work_jobs.each { |args| ImportWorkJob.perform_now(*args) }

          expect(importer.reload.status).to eq('Complete')
        end

        it 'stays pending while unseen entries are marked skipped' do
          status_while_skipping = nil
          allow(importer).to receive(:mark_unseen_as_skipped) do
            deferred_work_jobs.each { |args| ImportWorkJob.perform_now(*args) }
            status_while_skipping = Importer.find(importer.id).status
          end

          importer.import_objects(%w[collection work])

          expect(status_while_skipping).to eq('Pending')
        end
      end

      context 'when parsing fails' do
        before do
          allow(importer.parser).to receive(:works).and_raise(RuntimeError, 'unreadable row')
        end

        it 'leaves the importer failed' do
          importer.import_objects(%w[collection work])

          expect(importer.reload.status).to eq('Failed')
        end

        it 'records the failure before releasing the parsing hold' do
          allow(importer).to receive(:existing_entries?).and_return(true)
          allow(importer.parser).to receive(:rebuild_entries).and_raise(RuntimeError, 'unreadable row')
          status_at_release = nil
          allow(ImporterRun).to receive(:decrement_enqueued_records).and_wrap_original do |original, *args|
            status_at_release = Importer.find(importer.id).status
            original.call(*args)
          end

          importer.import_objects(%w[collection work])

          expect(status_at_release).to eq('Failed')
        end

        context 'after some jobs were already enqueued' do
          before do
            rows = Enumerator.new do |yielder|
              yielder << { source_identifier: 'work_1' }
              raise 'unreadable row'
            end
            allow(importer.parser).to receive(:works).and_return(rows)
            allow(ImportWorkJob).to receive(:perform_later) { |*args| deferred_work_jobs << args }
          end

          it 'leaves the importer failed when those jobs finish' do
            importer.import_objects(%w[collection work])
            deferred_work_jobs.each { |args| ImportWorkJob.perform_now(*args) }

            expect(importer.reload.status).to eq('Failed')
          end
        end
      end

      context 'when every job finishes while the parser is still running' do
        before do
          allow(ImportWorkJob).to receive(:perform_later) { |*args| ImportWorkJob.perform_now(*args) }
        end

        it 'marks the importer complete once the parser finishes' do
          importer.import_objects(%w[collection work])

          expect(importer.reload.status).to eq('Complete')
        end
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
