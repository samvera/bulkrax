# frozen_string_literal: true

module Bulkrax
  ##
  # The target data layer where we write and read our imported {Bulkrax::Entry} objects.
  module PersistenceLayer
    # We're inheriting from an ActiveRecord exception as that is something we know will be here; and
    # something that the main_app will be expect to be able to handle.
    class ObjectNotFoundError < ActiveRecord::RecordNotFound
    end

    # We're inheriting from an ActiveRecord exception as that is something we know will be here; and
    # something that the main_app will be expect to be able to handle.
    class RecordInvalid < ActiveRecord::RecordInvalid
    end

    class AbstractAdapter
      # @see ActiveFedora::Base.find
      def self.find(id)
        raise NotImplementedError, "#{self}.#{__method__}"
      end

      def self.solr_name(field_name)
        raise NotImplementedError, "#{self}.#{__method__}"
      end

      # @yield when Rails application is running in test environment.
      def self.clean!
        return true unless Rails.env.test?
        yield
      end

      def self.query(q, **kwargs)
        raise NotImplementedError, "#{self}.#{__method__}"
      end
    end
  end
end
