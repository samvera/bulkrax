# frozen_string_literal: true

require 'samvera/derivatives/configuration'

##
# Why Samvera and not Hyrax?  Because there are folks creating non-Hyrax applications that will
# almost certainly want to leverage this work.  And there might be switches for `defined?(Hyrax)`.
#
# Further the following four gems have interest in the interfaces of this module:
#
# - Hyrax
# - Hydra::Derivatives
# - Bulkrax
# - IiifPrint
#
# As such, it makes some sense to isolate the module and begin defining interfaces.
module Samvera
  ##
  # This module separates the finding/creation of a derivative binary (via {FileLocator}) and
  # applying that derivative to the FileSet (via {FileApplicator}).
  #
  # In working on the interface and objects there is an effort to preserve backwards functionality
  # while also allowing for a move away from that functionality.
  #
  # There are three primary concepts to consider:
  #
  # - Locator :: responsible for knowing where the derivative is
  # - Location :: responsible for encapsulating the location
  # - Applicator :: responsible for applying the located derivative to the FileSet
  #
  # The "trick" in this is in the polymorphism of the Location.  Let's say we have the following
  # desired functionality for the thumbnail derivative:
  #
  #   ```gherkin
  #   Given a FileSet
  #   When I provide a thumbnail derivative
  #   Then I want to add that as the thumbnail for the FileSet
  #
  #   Given a FileSet
  #   When I do not provide a thumbnail derivative
  #   Then I want to generate a thumbnail
  #     And add the generated as the thumbnail for the FileSet
  #   ```
  #
  # In the above case we would have two Locator strategies:
  #
  # - Find Existing One
  # - Will Generate One (e.g. Hyrax::FileSetDerivativesService with Hydra::Derivative behavior)
  #
  # And we would have two Applicator strategies:
  #
  # - Apply an Existing One
  # - Generate One and Apply (e.g. Hyrax::FileSetDerivativesService with Hydra::Derivative behavior)
  #
  # The Location from the first successful Locator will dictate how the ApplicatorStrategies do
  # their work.
  module Derivatives
    ##
    # @api public
    #
    # Responsible for configuration of derivatives.
    #
    # @example
    #   Samvera::Derivative.config do |config|
    #     config.register(type: :thumbnail, applicators: [CustomApplicator], locators: [CustomLocator]) do |file_set|
    #       file_set.video? || file_set.audio? || file_set.image?
    #     end
    #   end
    #
    # @yield [Configuration]
    #
    # @return [Configuration]
    def self.config
      @config ||= Configuration.new
      yield(@config) if block_given?
      @config
    end

    ##
    # @api public
    #
    # Locate the derivative for the given :file_set and apply it to that :file_set.
    #
    # @param file_set [FileSet]
    # @param derivative [Samvera::Derivatives::Configuration::RegisteredType]
    # @param file_path [String]
    #
    # @note As a concession to existing implementations of creating derivatives, file_path is
    #       included as a parameter.
    def self.locate_and_apply_derivative_for(file_set:, derivative:, file_path:)
      return false unless derivative.applicable_for?(file_set: file_set)

      from_location = FileLocator.call(
        file_set: file_set,
        file_path: file_path,
        derivative: derivative
      )

      FileApplicator.call(
        from_location: from_location,
        file_set: file_set,
        derivative: derivative
      )
    end

    ##
    # The purpose of this module is to find the derivative file path for a FileSet and a given
    # derivative type (e.g. :thumbnail).
    #
    # @see https://github.com/samvera-labs/bulkrax/issues/760 Design Document
    #
    # @note Ideally, this module would be part of Hyrax or Hydra::Derivatives
    # @see https://github.com/samvera/hyrax
    # @see https://github.com/samvera/hydra-derivatives
    module FileLocator
      ##
      # @api public
      #
      # This method is responsible for finding the correct file names for the given file set and
      # derivative type.
      #
      # @param file_set [FileSet]
      # @param file_path [String]
      # @param derivative [Samvera::Derivatives::Configuration::RegisteredType]
      #
      # @return [Samvera::Derivatives::FromLocation]
      #
      # @note Why {.call}?  This allows for a simple lambda interface, which can greatly ease testing
      #       and composition.
      def self.call(file_set:, file_path:, derivative:)
        from_location = nil

        derivative.locators.each do |locator|
          from_location = locator.locate(
            file_set: file_set,
            file_path: file_path,
            derivative_type: derivative.type
          )
          break if from_location.present?
        end

        from_location
      end

      ##
      # @abstract
      #
      # The purpose of this abstract class is to provide the public interface for strategies.
      #
      # @see {.find}
      class Strategy
        ##
        # @api public
        # @param file_set [FileSet]
        # @param file_path [String]
        # @param derivative_type [#to_sym]
        #
        # @return [Samvera::Derivatives::FromLocation] when this is a valid strategy
        # @return [NilClass] when this is not a valid strategy
        def self.locate(file_set:, file_path:, derivative_type:)
          raise NotImplementedError
        end
      end
    end

    module FileApplicator
      ##
      # @api public
      #
      # @param file_set [FileSet]
      # @param from_location [#present?]
      # @param derivative [Array<#apply!>]
      def self.call(file_set:, from_location:, derivative:)
        # rubocop:disable Rails/Blank
        return false unless from_location.present?
        # rubocop:enable Rails/Blank

        derivative.applicators.each do |applicator|
          applicator.apply!(file_set: file_set, derivative_type: derivative.type, from_location: from_location)
        end
      end

      ##
      # @abstract
      #
      # The purpose of this abstract class is to provide the public interface for strategies.
      #
      # @see {.find}
      class Strategy
        # In some cases the FromLocation knows how to write itself; this is the case when we wrap
        # the Hyrax::FileSetDerivativesService.
        class_attribute :delegate_apply_to_given_from_location, default: false

        ##
        # @param file_set [FileSet]
        # @param derivative_type [#to_sym]
        # @param from_location [Object]
        def self.apply!(file_set:, derivative_type:, from_location:)
          new(file_set: file_set, derivative_type: derivative_type, from_location: from_location).apply!
        end

        def initialize(file_set:, derivative_type:, from_location:)
          @file_set = file_set
          @derivative_type = derivative_type
          @from_location = from_location
        end
        attr_reader :file_set, :derivative_type, :from_location

        # @note What's going on with this logic?  To continue to leverage
        #       Hyrax::FileSetDerivativesService, we want to let that wrapped service (as a
        #       FromLocation) to do it's original work.  However, we might have multiple strategies
        #       in play for application.  That case is when we want to first check for an existing
        #       thumbnail and failing that generate the thumbnail.  The from_location could either
        #       be the found thumbnail...or it could be the wrapped Hyrax::FileSetDerivativesService
        #       that will create the thumbnail and write it to the location.  The two applicator
        #       strategies in that case would be the wrapper and logic that will write the found
        #       file to the correct derivative path.
        def apply!
          if delegate_apply_to_given_from_location?
            return false unless from_location.respond_to?(:apply!)

            from_location.apply!(file_set: file_set, derivative_type: derivative_type)
          else
            return false if from_location.respond_to?(:apply!)

            perform_apply!
          end
        end

        private

        def perform_apply!
          raise NotImplementedError
        end
      end
    end
  end
end
