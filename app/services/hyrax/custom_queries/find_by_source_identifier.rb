# frozen_string_literal: true

module Hyrax
  module CustomQueries
    ##
    # @see https://github.com/samvera/valkyrie/wiki/Queries#custom-queries
    class FindBySourceIdentifier
      def self.queries
        [:find_by_model_and_property_value]
      end

      def initialize(query_service:)
        @query_service = query_service
      end

      attr_reader :query_service
      delegate :resource_factory, to: :query_service
      delegate :orm_class, to: :resource_factory

      ##
      # @param model [Class, #internal_resource]
      # @param property [#to_s] the name of the property we're attempting to
      #        query.
      # @param value [#to_s] the propety's value that we're trying to match.
      #
      # @return [NilClass] when no record was found
      # @return [Valkyrie::Resource] when a record was found
      #
      # @note This is not a real estate transaction nor a Zillow lookup.
      def find_by_model_and_property_value(model:, property:, value:)
        sql_query = sql_for_find_by_model_and_property_value
        # NOTE: Do we need to ask the model for it's internal_resource?
        # TODO: no => undefined method `internal_resource' for Image:Class
        query_service.run_query(sql_query, model, property, value).first
      end

      private

      def sql_for_find_by_model_and_property_value
        # NOTE: This is querying the first element of the property, but we might
        # want to check all of the elements.
        <<-SQL
          SELECT * FROM orm_resources
          WHERE internal_resource = ? AND metadata -> ? ->> 0 = ?
          LIMIT 1;
        SQL
      end
    end
  end
end
