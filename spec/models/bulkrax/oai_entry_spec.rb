require 'rails_helper'

module Bulkrax
  RSpec.describe OaiEntry, type: :model do
    let(:entry) { described_class.new(importer: importer) }
    let(:importer) { FactoryBot.build(:bulkrax_importer_oai) }
    let(:collection) { FactoryBot.build(:collection) }

    describe 'collections created' do
      context 'All' do
        before do
          importer.parser_fields['set'] = 'all'
        end

        it 'expects 0 collections where sets are blank' do
          allow(entry).to receive(:sets).and_return(nil)
          expect(entry.collections_created?).to be_truthy
        end

        it 'expects collections for all sets' do
          allow(entry).to receive_message_chain(:sets, :exist?).and_return(true)
          allow(entry).to receive_message_chain(:sets, :size).and_return(5)
          expect(entry.collections_created?).to be_falsey
        end

        it 'expects collections for all sets' do
          entry.collection_ids = [1, 2, 3, 4, 5]
          allow(entry).to receive_message_chain(:sets, :exist?).and_return(true)
          allow(entry).to receive_message_chain(:sets, :size).and_return(5)
          expect(entry.collections_created?).to be_truthy
        end
      end

      context 'Single Set' do
        before do
          importer.parser_fields['set'] = 'some_set'
        end

        it 'expects only one collection - false if there are none' do
          expect(entry.collections_created?).to be_falsey
        end

        it 'expects only one collection - false if there are more' do
          entry.collection_ids = [1, 2]
          expect(entry.collections_created?).to be_falsey
        end

        it 'expects only one collection' do
          entry.collection_ids = [1]
          expect(entry.collections_created?).to be_truthy
        end
      end
    end

    describe "find_or_create_collection_ids" do
      before do
        importer.parser_fields['set'] = 'some_set'
        allow(entry).to receive_message_chain(:sets, :blank?).and_return(false)
      end

      it 'expects only one collection' do
        allow(Collection).to receive(:where).and_return([collection])
        entry.find_or_create_collection_ids
        expect(entry.collection_ids.length).to eq(1)
      end
      it 'fails if there is no collection' do
        allow(Collection).to receive(:where).and_return([])
        entry.find_or_create_collection_ids
        expect(entry.collection_ids.length).to eq(0)
      end
    end
  end
end
