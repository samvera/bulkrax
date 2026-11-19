# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::RemoveRelationshipsForImporter do
  # Alas fellow traveller, there is not much that I'm going to test.  To test the edge cases of this
  # script requires significant setup; numerous works and collections and relationships.
  #
  # Further this script is basically a test for something that RDBMs handle with referential integrity tools.
  describe ".break_relationships_for!" do
    subject(:remover) { described_class.break_relationships_for!(importer: importer, with_progress_bar: false) }
    let(:importer) { FactoryBot.create(:bulkrax_importer) }
    let(:entry) { FactoryBot.create(:bulkrax_entry, importerexporter: importer) }
    let(:importer_run) { FactoryBot.create(:bulkrax_importer_run, importer: importer) }

    it "breaks relationships for the entries associated with the given importer" do
      # rubocop:disable RSpec/VerifiedDoubles
      found = double("The Found Object that looks like a work",
                     member_of_works: [],
                     member_works: [],
                     save!: true)
      allow(found).to receive(:member_of_collections=).with([])
      # rubocop:enable RSpec/VerifiedDoubles

      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Bulkrax::ObjectFactory).to receive(:find).and_return(found)
      # rubocop:enable RSpec/AnyInstance
      entry.statuses.create!(status_message: "Complete", runnable: importer_run)
      remover
    end
  end

  describe "#remove_relationships_from_collection" do
    subject(:remover) { described_class.new(entries: [], progress_bar: described_class::NullProgressBar) }
    # rubocop:disable RSpec/VerifiedDoubles
    let(:parent_collection) { double("parent collection") }
    let(:child_collection) { double("child collection") }
    let(:collection) do
      double("collection", member_works: [], member_of_collections: [parent_collection], member_collections: [child_collection])
    end
    # rubocop:enable RSpec/VerifiedDoubles

    before { allow(Hyrax::Collections::NestedCollectionPersistenceService).to receive(:remove_nested_relationship_for) }

    it "removes the collection from its parent collections and its child collections from it" do
      remover.remove_relationships_from_collection(collection)

      expect(Hyrax::Collections::NestedCollectionPersistenceService)
        .to have_received(:remove_nested_relationship_for).with(parent: parent_collection, child: collection)
      expect(Hyrax::Collections::NestedCollectionPersistenceService)
        .to have_received(:remove_nested_relationship_for).with(parent: collection, child: child_collection)
    end

    it "leaves collection links alone without Hyrax" do
      allow(Bulkrax).to receive(:hyrax_loaded?).and_return(false)

      remover.remove_relationships_from_collection(collection)

      expect(Hyrax::Collections::NestedCollectionPersistenceService).not_to have_received(:remove_nested_relationship_for)
    end
  end
end
