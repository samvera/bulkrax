# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  # NOTE: Unable to put this file in spec/factories/bulkrax (where it would mirror the path in app/) because
  # (presumably) FactoryBot autoloads all files in spec/factories, which would always run this spec.
  # Why aren't there more tests?  In part because so much of the ObjectFactory require that we boot
  # up Fedora and SOLR; something that remains non-desirous due to speed.

  RSpec.describe ValkyrieObjectFactory do

    describe '.search_by_property' do
      let(:collections) do
        [
          FactoryBot.build(:collection, title: ["Specific Title"]),
          FactoryBot.build(:collection, title: ["Title"])
        ]
      end
      let(:klass) { double(where: collections) }
      before do
        # Valkyrie::MetadataAdapter.register(
        #   Freyja::MetadataAdapter.new,
        #   :freyja
        # )
        # Valkyrie.config.metadata_adapter = :freyja
        # byebug
        Wings::ModelRegistry.register(CollectionResource, Collection)
        # allow(Hyrax).to receive(:query_service).and_return(Freyja::MetadataAdapter.new)
      end
      it 'does find the collection with a partial match' do
        collection = described_class.search_by_property(
          value: "Title", 
          search_field: "bulkrax_identifier_tesim",
          name_field: :bulkrax_identifier,
          klass: klass
        )
        expect(collection.title).to eq(["Title"])
      end
    end
  end
end
