# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe OaiEntry, type: :model do
    let(:entry) { described_class.new(importerexporter: importer) }
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

    describe "find_collection_ids" do
      before do
        importer.parser_fields['set'] = 'MyCollection'
        allow(entry).to receive_message_chain(:sets, :blank?).and_return(false)
      end

      it 'expects only one collection' do
        allow(Collection).to receive(:where).and_return([collection])
        entry.find_collection_ids
        expect(entry.collection_ids.length).to eq(1)
      end
      it 'fails if there is no collection' do
        allow(Collection).to receive(:where).and_return([])
        entry.find_collection_ids
        expect(entry.collection_ids.length).to eq(0)
      end
    end

    context 'with specified admin set' do
      let(:mapping) do
        {
          'parents' => { 'from' => ['parents'] },
          'children' => { 'from' => ['children'] }
        }
      end

      before do
        importer.parser_fields['thumbnail_url'] = ''
        allow(entry.class).to receive(:parents_field).and_return('parents')
        allow(entry.class).to receive(:children_field).and_return('children')
        allow(entry).to receive(:mapping).and_return(mapping)
      end

      it 'adds admin set id to parsed metadata' do
        allow(entry).to receive_message_chain(:record, :header, :identifier).and_return("some_identifier")
        allow(entry).to receive_message_chain(:record, :header, :set_spec).and_return([])
        allow(entry).to receive_message_chain(:record, :metadata, :children).and_return([])
        allow(entry).to receive_message_chain(:raw_metadata, :[]).and_return({ children: [], parents: [] })
        entry.build_metadata
        expect(entry.parsed_metadata['admin_set_id']).to eq 'MyString'
      end
    end
  end
end
