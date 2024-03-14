# frozen_string_literal: true

module Bulkrax
  RSpec.shared_examples 'dynamic record lookup' do
    let(:importer) { FactoryBot.create(:bulkrax_importer_csv_complex) }
    let(:importer_id) { importer.id }
    let(:importer_run_id) { importer.current_run.id }

    before do
      allow(::Hyrax.config).to receive(:curation_concerns).and_return([Work])
      # DRY spec setup -- by default, assume #find_record doesn't find anything
      allow(Entry).to receive(:find_by).and_return(nil)
      allow(Bulkrax.object_factory).to receive(:find).and_return(nil)
    end

    describe '#find_record' do
      context 'when passed a Bulkrax source_identifier' do
        let(:source_identifier) { 'bulkrax_identifier_1' }

        it 'looks through entries and all work types' do
          expect(Entry).to receive(:find_by).with({ identifier: source_identifier, importerexporter_type: 'Bulkrax::Importer', importerexporter_id: importer_id }).once
          expect(Bulkrax.object_factory).to receive(:find).with(source_identifier).once.and_return(Bulkrax::ObjectFactoryInterface::ObjectNotFoundError)

          subject.find_record(source_identifier, importer_run_id)
        end

        context 'when an entry is found' do
          let(:entry) { create(:bulkrax_csv_entry_work, importerexporter: importer) }
          let(:factory) { instance_double(ObjectFactory, find: record) }
          let(:record) { instance_double(::Work, title: ["Found through Entry's factory"]) }

          before do
            allow(Entry).to receive(:find_by).with({ identifier: source_identifier, importerexporter_type: 'Bulkrax::Importer', importerexporter_id: importer_id }).and_return(entry)
            allow(entry).to receive(:factory).and_return(factory)
          end

          it "returns the entry's record" do
            expect(subject.find_record(source_identifier, importer_run_id)[1]).to eq(record)
          end

          it "uses the entry's factory to find its record" do
            expect(entry).to receive(:factory)
            expect(factory).to receive(:find)

            found_entry, found_record = subject.find_record(source_identifier, importer_run_id)

            expect(found_record.title).to eq(record.title)
            expect(found_entry.identifier).to eq(entry.identifier)
          end
        end

        context 'when nothing is found' do
          it 'returns nil' do
            expect(subject.find_record(source_identifier, importer_run_id)[1]).to be_nil
          end
        end
      end

      context 'when passed an ID' do
        let(:id) { 'xyz6789' }

        it 'looks through entries and all work types' do
          expect(Entry).to receive(:find_by).with({ identifier: id, importerexporter_type: 'Bulkrax::Importer', importerexporter_id: importer_id }).once
          expect(Bulkrax.object_factory).to receive(:find).with(id).once.and_return(nil)

          subject.find_record(id, importer_run_id)
        end

        context 'when a collection is found' do
          let(:collection) { Bulkrax.collection_model_class.new }

          before do
            allow(Bulkrax.object_factory).to receive(:find).with(id).and_return(collection)
          end

          it 'returns the collection' do
            expect(subject.find_record(id, importer_run_id)[1]).to eq(collection)
          end
        end

        context 'when a work is found' do
          let(:work) { instance_double(::Work) }

          before do
            allow(Bulkrax.object_factory).to receive(:find).with(id).and_return(work)
          end

          it 'returns the work' do
            expect(subject.find_record(id, importer_run_id)[1]).to eq(work)
          end
        end

        context 'when nothing is found' do
          it 'returns nil' do
            expect(subject.find_record(id, importer_run_id)[1]).to be_nil
          end
        end
      end
    end
  end
end
