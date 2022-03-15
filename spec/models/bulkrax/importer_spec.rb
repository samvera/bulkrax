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
  end
end
