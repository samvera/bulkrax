# frozen_string_literal: true

module Samvera
  module Derivatives
    # The default behavior of {Hyrax::FileSetDerivativesService} is to create a derivative and then
    # apply it to the FileSet.  This module wraps that behavior such that we can leverage the
    # {Samvera::Derivatives} module and interfaces to handle cases where some of the derivatives
    # already exist.
    module Hyrax
      # @note This conforms to the {Hyrax::DerivativeService} interface.  The intention of this
      #       class is to be the sole registered {Hyrax::DerivativeService.services}
      class ServiceShim
        # @param file_set [FileSet]
        # @param candidate_derivative_types [Array<Symbol>] the possible types of derivatives that
        #        we could create for this file_set.
        # @param config [#registry_for]
        #
        # @todo We will want some kind of lambda to determine the candidate_derivative_types for this
        #       file_set.
        def initialize(file_set, candidate_derivative_types: [], config: Samvera::Derivatives.config)
          @file_set = file_set
          @config = config
          @derivatives = candidate_derivative_types.map { |type| config.registry_for(type: type) }
        end

        attr_reader :file_set

        # @return [Array<Samvera::Derivatives::Configuration::RegisteredType>]
        attr_reader :derivatives
        attr_reader :config

        def valid?
          # We have a file set, which also means a parent work.  I believe we always want this to be
          # valid, because we want to leverage the locator/applicator behavior instead of the
          # implicit work.
          true
        end

        def cleanup_derivatives; end

        # We have two vectors of consideration for derivative generation:
        #
        # - The desired derivatives for a file_set's parent work (e.g. the candidate derivatives)
        # - The available derivatives for a file_set's mime type
        def create_derivatives(file_path)
          derivatives.each do |derivative|
            Samvera::Derivatives.locate_and_apply_derivative_for(
              file_set: file_set,
              file_path: file_path,
              derivative: derivative
            )
          end
        end

        def derivative_url(_destination_name)
          ""
        end
      end

      class FileApplicatorStrategy < Samvera::Derivatives::FileApplicator::Strategy
        # With this set to true, we're telling the applicator to use the from_location
        # (e.g. {Samvera::Derivatives::Hyrax::FileSetDerivativesServiceWrapper}) to apply the
        # derivatives.
        self.delegate_apply_to_given_from_location = true
      end

      class FileLocatorStrategy < Samvera::Derivatives::FileLocator::Strategy
        # Implements {Samvera::Derivatives::FileLocator::Strategy} interface.
        #
        # @see Samvera::Derivatives::FileLocator::Strategy
        #
        # @return [Samvera::Derivatives::Hyrax::FileSetDerivativesServiceWrapper]
        def self.locate(file_set:, file_path:, **)
          file_set.samvera_derivatives_default_from_location_wrapper(file_path: file_path)
        end
      end

      class FileSetDerivativesServiceWrapper
        class_attribute :wrapped_derivative_service_class, default: ::Hyrax::FileSetDerivativesService

        # @param file_set [FileSet]
        # @param file_path [String]
        def initialize(file_set:, file_path:)
          @file_set = file_set
          @file_path = file_path
          @wrapped_derivative_service = wrapped_derivative_service_class.new(file_set)
        end
        attr_reader :file_set, :wrapped_derivative_service, :file_path

        # @see Samvera::Derivatives::FileLocator.call
        def present?
          true
        end

        # @see Samvera::Derivatives::FileApplicator::Strategy
        def apply!(*)
          # Why the short-circuit? By the nature of the underlying
          # ::Hyrax::FileSetDerivativesService, we generate multiple derivatives in one pass.  But
          # with the implementation of Samvera::Derivatives, we declare the derivatives and then
          # iterate on locating and applying them.  With this short-circuit, we will only apply the
          # derivatives once.
          return true if defined?(@already_applied)

          return false unless wrapped_derivative_service.valid?

          wrapped_derivative_service.create_derivatives(file_path)
          @already_applied = true
        end
      end

      ##
      # The purpose of this module is to preserve the existing Hyrax derivative behavior while also
      # allowing for the two-step tango of locator and applicator.
      #
      # @see Samvera::Derivatives.locate_and_apply_derivative_for
      module FileSetDecorator
        # @return [Samvera::Derivatives::Hyrax::FileSetDerivativesServiceWrapper]
        def samvera_derivatives_default_from_location_wrapper(file_path:)
          @samvera_derivatives_default_from_location_wrapper ||=
            Samvera::Derivatives::Hyrax::FileSetDerivativesServiceWrapper.new(file_set: self, file_path: file_path)
        end
      end
    end
  end
end

# TODO: We are likely going to want that.
# Hyrax::DerivativeService.services = [Samvera::Derivatives::Hyrax::ServiceShim]
FileSet.prepend(Samvera::Derivatives::Hyrax::FileSetDecorator)
