module Bulkrax
  module WithAssociatedCollection
    extend ActiveSupport::Concern

    # Strip out the :collection key, and add the member_of_collection_ids,
    # which is used by Hyrax::Actors::AddAsMemberOfCollectionsActor
    def create_attributes
      return super if attributes[:collection].nil?
      super.except(:collection).merge(member_of_collection_ids: [collection.id])
    end

    # Strip out the :collection key, and add the member_of_collection_ids,
    # which is used by Hyrax::Actors::AddAsMemberOfCollectionsActor
    def update_attributes
      return super if attributes[:collection].nil?
      super.except(:collection).merge(member_of_collection_ids: [collection.id])
    end

    private

    def collection
      @collection ||= CollectionFactory.new(attributes.fetch(:collection)).find_or_create
      @collection.reindex_extent = Hyrax::Adapters::NestingIndexAdapter::LIMITED_REINDEX
      return @collection
    end
  end
end
