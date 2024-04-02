# frozen_string_literal: true

module Wings
  module CustomQueries
    class FindBySourceIdentifier
      # Custom query override specific to Wings

      def self.queries
        [:find_by_model_and_property_value]
      end

      attr_reader :query_service
      delegate :resource_factory, to: :query_service

      def initialize(query_service:)
        @query_service = query_service
      end

      def find_by_model_and_property_value(model:, property:, value:, use_valkyrie: Hyrax.config.use_valkyrie?)
        # NOTE: This is using the Bulkrax::ObjectFactory (e.g. the one
        # envisioned for ActiveFedora).  In doing this, we avoid the situation
        # where Bulkrax::ValkyrieObjectFactory calls this custom query.
        af_object = Bulkrax::ObjectFactory.search_by_property(value: value, klass: model, field: property)

        return if af_object.blank?
        return af_object unless use_valkyrie

        resource_factory.to_resource(object: af_object)
      end
    end
  end
end
