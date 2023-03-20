# frozen_string_literal: true

module Samvera
  module Derivatives
    ##
    # The purpose of this class is to contain the explicit derivative generation directives for the
    # upstream application.
    #
    # @note The implicit deriviate types for Hyrax are as follows:
    #       - type :extracted_text with sources [:pdf, :office_document]
    #       - type :thumbnail with sources [:pdf, :office_document, :thumbnail, :image]
    #       - type :mp3 with sources [:audio]
    #       - type :ogg with sources [:audio]
    #       - type :webm with sources [:video]
    #       - type :mp4 with sources [:video]
    #
    # @note A long-standing practice of Samvera's Hyrax has been to have assumptive and implicit
    #       derivative generation (see Hyrax::FileSetDerivativesService).  In being implicit, a
    #       challenge arises, namely overriding and configuring.  There exists a crease in the code
    #       to allow for a different derivative approach (see Hyrax::DerivativeService).  Yet that
    #       approach continues the tradition of implicit work.
    class Configuration
      def initialize
        # Favoring a Hash for ease of lookup as well as the concept that there can be only one entry
        # per type.
        @registered_types = {}
      end

      # TODO: Consider the appropriate extension
      RegisteredType = Struct.new(:type, :locators, :applicators, :applicability, keyword_init: true) do
        def applicable_for?(file_set:)
          applicability.call(file_set)
        end
      end

      ##
      # @api pulic
      #
      # @param type [Symbol] The named type of derivative
      # @param locators [Array<Samvera::Derivatives::FileLocator::Strategy>] The strategies that
      #        we'll attempt in finding the derivative that we will later apply.
      # @param applicators [Array<Samvera::Derivatives::FileApplicator::Strategy>] The strategies
      #        that we'll use to apply the found derivative to the {FileSet}
      #
      # @yieldparam applicability [#call]
      #
      # @return [RegisteredType]
      #
      # @note What is the best mechanism for naming the sources?  At present we're doing a lot of
      #       assumption on the types.
      def register(type:, locators:, applicators:, &applicability)
        # Should the validator be required?
        @registered_types[type.to_sym] = RegisteredType.new(
          type: type.to_sym,
          locators: Array(locators),
          applicators: Array(applicators),
          applicability: applicability || default_applicability
        )
      end

      ##
      # @api public
      #
      # @param type [Symbol]
      #
      # @return [RegisteredType]
      def registry_for(type:)
        @registered_types.fetch(type.to_sym) { empty_registry_for(type: type.to_sym) }
      end

      private

      def empty_registry_for(type:)
        RegisteredType.new(type: type, locators: [], applicators: [], applicability: ->(_file_set) { false })
      end

      # We're going to assume this is true unless configured otherwise.
      def default_applicability
        ->(_file_set) { true }
      end
    end
  end
end
