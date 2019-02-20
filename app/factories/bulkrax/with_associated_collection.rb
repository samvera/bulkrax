module Bulkrax
  module WithAssociatedCollection
    extend ActiveSupport::Concern

    # Strip out the :collection key, and add the member_of_collection_ids,
    # which is used by Hyrax::Actors::AddAsMemberOfCollectionsActor
    def create_attributes
      if attributes[:collection].present?
        super.except(:collections).merge(member_of_collections_attributes: {0 => {id: collection.id}})
      elsif attributes[:collections].present?
        collection_ids = attributes[:collections].each.with_index.inject({}) do |ids, (element, index)|
          ids[index] = element
          ids
        end
        super.except(:collections).merge(member_of_collections_attributes: collection_ids)
      else
        super
      end
    end

    # Strip out the :collection key, and add the member_of_collection_ids,
    # which is used by Hyrax::Actors::AddAsMemberOfCollectionsActor
    def update_attributes
      if attributes[:collection].present?
        super.except(:collections).merge(member_of_collections_attributes: {0 => {id: collection.id}})
      elsif attributes[:collections].present?
        collection_ids = attributes[:collections].each.with_index.inject({}) do |ids, (element, index)|
          ids[index] = element
          ids
        end
        super.except(:collections).merge(member_of_collections_attributes: collection_ids)
      else
        super
      end
    end

    private

    def collection(attrs=nil)
      attrs ||= attributes.fetch(:collection)
      @collection ||= CollectionFactory.new(attrs).find_or_create
      @collection.reindex_extent = Hyrax::Adapters::NestingIndexAdapter::LIMITED_REINDEX
      return @collection
    end
  end
end
