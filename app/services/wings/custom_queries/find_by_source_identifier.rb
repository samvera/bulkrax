# frozen_string_literal: true

return unless defined?(Wings)

module Wings
  module CustomQueries
    class FindBySourceIdentifier
      # Custom query override specific to Wings

      def self.queries
        [:find_by_property_value]
      end

      attr_reader :query_service
      delegate :resource_factory, to: :query_service

      def initialize(query_service:)
        @query_service = query_service
      end

      # rubocop:disable Lint/UnusedMethodArgument
      def find_by_property_value(property:, value:, search_field:, use_valkyrie: Hyrax.config.use_valkyrie?)
        # rubocop:enable Lint/UnusedMethodArgument
        # NOTE: This is using the Bulkrax::ObjectFactory (e.g. the one envisioned for ActiveFedora).
        # In doing this, we avoid the situation where Bulkrax::ValkyrieObjectFactory calls this custom query.

        # This is doing a solr search first, so we have to use the search_field instead of the property for "field"
        # If it cannot find the object in Solr, it falls back to an ActiveFedora search, if the object is an ActiveFedora object
        af_object = Bulkrax::ObjectFactory.search_by_property(
          value: value,
          klass: ActiveFedora::Base,
          field: search_field,
          name_field: property
        )

        return if af_object.blank?
        return af_object unless use_valkyrie

        resource_factory.to_resource(object: af_object)
      end
    end
  end
end
