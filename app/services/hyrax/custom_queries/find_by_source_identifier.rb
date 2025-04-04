# frozen_string_literal: true

module Hyrax
  module CustomQueries
    ##
    # @see https://github.com/samvera/valkyrie/wiki/Queries#custom-queries
    class FindBySourceIdentifier
      def self.queries
        [:find_by_property_value]
      end

      def initialize(query_service:)
        @query_service = query_service
      end

      attr_reader :query_service
      delegate :resource_factory, to: :query_service
      delegate :orm_class, to: :resource_factory

      ##
      # @param property [#to_s] the name of the property we're attempting to
      #        query.
      # @param value [#to_s] the propety's value that we're trying to match.
      #
      # @return [NilClass] when no record was found
      # @return [Valkyrie::Resource] when a record was found
      def find_by_property_value(property:, value:, **)
        sql_query = sql_for_find_by_property_value
        query_service.run_query(sql_query, property, value.to_s).first
      end

      private

      def sql_for_find_by_property_value
        # NOTE: This is querying the first element of the property, but we might
        # want to check all of the elements.
        <<-SQL
          SELECT * FROM orm_resources
          WHERE metadata -> ? ->> 0 = ?
          LIMIT 1;
        SQL
      end
    end
  end
end
