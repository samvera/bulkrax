# frozen_string_literal: true

module Bulkrax
  ##
  # A module that helps define the expected interface for object factory interactions.
  #
  # The abstract class methods are useful for querying the underlying persistence layer when you are
  # not in the context of an instance of an {Bulkrax::ObjectFactory} and therefore don't have access
  # to it's {#find} instance method.
  #
  # @abstract
  module ObjectFactoryInterface
    extend ActiveSupport::Concern
    # We're inheriting from an ActiveRecord exception as that is something we know will be here; and
    # something that the main_app will be expect to be able to handle.
    class ObjectNotFoundError < ActiveRecord::RecordNotFound
    end

    # We're inheriting from an ActiveRecord exception as that is something we know will be here; and
    # something that the main_app will be expect to be able to handle.
    class RecordInvalid < ActiveRecord::RecordInvalid
    end

    class_methods do
      ##
      # @see ActiveFedora::Base.find
      def find(id)
        raise NotImplementedError, "#{self}.#{__method__}"
      end

      def solr_name(field_name)
        raise NotImplementedError, "#{self}.#{__method__}"
      end

      # @yield when Rails application is running in test environment.
      def clean!
        return true unless Rails.env.test?
        yield
      end

      def query(q, **kwargs)
        raise NotImplementedError, "#{self}.#{__method__}"
      end
    end
  end
end
