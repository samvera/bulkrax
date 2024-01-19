# frozen_string_literal: true

module Bulkrax
  module PersistenceLayer
    class ActiveFedoraAdapter < AbstractAdapter
      def self.find(id)
        ActiveFedora::Base.find(id)
      rescue ActiveFedora::ObjectNotFoundError => e
        raise PersistenceLayer::RecordNotFound, e.message
      end

      def self.query(q, **kwargs)
        ActiveFedora::SolrService.query(q, **kwargs)
      end

      def self.clean!
        super do
          ActiveFedora::Cleaner.clean!
        end
      end

      def self.solr_name(field_name)
        ActiveFedora.index_field_mapper.solr_name(field_name)
      end
    end
  end
end
