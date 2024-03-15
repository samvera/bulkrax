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
      # @note This does not save either object.  We need to do that in another
      #       loop.  Why?  Because we might be adding many items to the parent.
      def add_child_to_parent_work(parent:, child:)
        raise NotImplementedError, "#{self}.#{__method__}"
      end

      def add_resource_to_collection(collection:, resource:, user:)
        raise NotImplementedError, "#{self}.#{__method__}"
      end

      ##
      # @yield when Rails application is running in test environment.
      def clean!
        return true unless Rails.env.test?
        yield
      end

      ##
      # @param resource [Object] something that *might* have file_sets members.
      def update_index_for_file_sets_of(resource:)
        raise NotImplementedError, "#{self}.#{__method__}"
      end

      ##
      # @return [Array<String>]
      def export_properties
        raise NotImplementedError, "#{self}.#{__method__}"
      end

      ##
      # @see ActiveFedora::Base.find
      def find(id)
        raise NotImplementedError, "#{self}.#{__method__}"
      end

      def find_or_nil(id)
        find(id)
      rescue NotImplementedError => e
        raise e
      rescue
        nil
      end

      def publish(event:, **kwargs)
        raise NotImplementedError, "#{self}.#{__method__}"
      end

      def query(q, **kwargs)
        raise NotImplementedError, "#{self}.#{__method__}"
      end

      def save!(resource:, user:)
        raise NotImplementedError, "#{self}.#{__method__}"
      end

      # rubocop:disable Metrics/ParameterLists
      def search_by_property(value:, klass:, field: nil, search_field: nil, name_field: nil, verify_property: false)
        raise NotImplementedError, "#{self}.#{__method__}"
      end

      def solr_name(field_name)
        raise NotImplementedError, "#{self}.#{__method__}"
      end

      ##
      # @param resources [Array<Object>]
      def update_index(resources: [])
        raise NotImplementedError, "#{self}.#{__method__}"
      end
      # rubocop:enable Metrics/ParameterLists
    end
  end
end
