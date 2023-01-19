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

    describe '#build_metadata' do
      before do
        # NOTE: Not up for messing with the thumbnail url
        importer.parser_fields['thumbnail_url'] = ''
        class ::Avacado < Work
          property :shape, predicate: ::RDF::Vocab::DC.format
        end
      end
      after do
        Object.send(:remove_const, :Avacado)
      end

      # rubocop:disable RSpec/VerifiedDoubles
      let(:nodes) do
        [double(children:
                # NOTE: The order of these matter.  I need to process "shape" first to
                # verify that we are properly setting the factory_class before delving into
                # the other metadata.
                [
                  double(name: "shape", content: "Lumpy and Kind of Brown"),
                  double(name: "model", content: "Avacado")
                ])]
      end
      # rubocop:enable RSpec/VerifiedDoubles

      it 'derives the factory class before proceeding with adding other metadata' do
        # TODO: Not a big fan of this method chain antics.  Ideally we'd pass in the object at
        # instantiation time.  However I'm cribbing past work and trying to get this fix out into
        # the wild.
        allow(entry).to receive_message_chain(:record, :header, :identifier).and_return("some_identifier")
        allow(entry).to receive_message_chain(:record, :header, :set_spec).and_return([])
        allow(entry).to receive_message_chain(:record, :metadata, :children).and_return(nodes)
        allow(entry).to receive_message_chain(:raw_metadata, :[]).and_return({ children: [], parents: [] })
        # Verifying that I have field mappings
        expect(entry.parser.model_field_mappings).to eq(["model"])
        entry.build_metadata
        expect(entry.factory_class).to eq(Avacado)
        expect(entry.parsed_metadata["shape"]).to eq(["Lumpy and Kind of Brown"])
      end
    end

    context 'with specified admin set' do
      let(:mapping) do
        {
          'parents' => { 'from' => ['parents'], related_parents_field_mapping: true },
          'children' => { 'from' => ['children'], related_children_field_mapping: true }
        }
      end

      before do
        importer.parser_fields['thumbnail_url'] = ''
        allow(entry).to receive(:mapping).and_return(mapping)
        allow(importer).to receive(:mapping).and_return(mapping)
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
