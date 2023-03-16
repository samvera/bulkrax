# frozen_string_literal: true

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
  # @todo Consider how we might bundle/adapt the existing Hyrax::FileSetDerivativesService to serve
  #       as both a locator and an applicator.  What would need to be true?  Conceptually it's a bit
  #       challenging because the mapping of behavior is different.  However, it would be possible
  #       to have the FileLocator fail to return any paths and then if the paths are nil, run the
  #       corresponding Hyrax::FileSetDerivativesService; which because of the many different types
  #       might result in attempting to create multiple derivatives.
  module Derivatives
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
      # @param derivative_type [#to_sym]
      # @param strategies [Array<#find>]
      #
      # @return [Array<String>] path to files that are the desired derivative type.
      #
      # @note Why {.call}?  This allows for a simple lambda interface, which can greatly ease testing
      #       and composition.
      def self.call(file_set:, derivative_type:, strategies: default_strategies)
        paths = nil

        strategies.each do |strategy|
          paths = strategy.find(file_set: file_set, derivative_type: derivative_type)
          break if paths.present?
        end

        # TODO: How do we handle the nil case?
        paths
      end

      def self.default_strategies
        [Strategy]
      end
      private_class_method :default_strategies

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
        # @param derivative_type [#to_sym]
        #
        # @return [Array<String>] when this is a valid strategy
        # @return [NilClass] when this is not a valid strategy
        def self.find(file_set:, derivative_type:)
          raise NotImplementedError
        end
      end
    end

    module FileApplicator
      ##
      # @api
      #
      # @param file_set [FileSet]
      # @param derivative_type [#to_sym]
      # @param from_paths [Array<String>] the paths of the files that are to be applied/written to
      #        the :file_set
      # @param strategies [Array<#write!>]
      def self.call(file_set:, derivative_type:, from_paths:, strategies: default_strategies)
        strategies.each do |strategy|
          strategy.write!(file_set: file_set, derivative_type: derivative_type, from_paths: from_paths)
        end
      end

      def self.default_strategies
        [Strategy]
      end
      private_class_method :default_strategies

      ##
      # @abstract
      #
      # The purpose of this abstract class is to provide the public interface for strategies.
      #
      # @see {.find}
      class Strategy
        ##
        # @param file_set [FileSet]
        # @param derivative_type [#to_sym]
        # @param from_paths [Array<String>] the paths of the files that are to be applied/written to
        #        the :file_set
        def self.write!(file_set:, derivative_type:, from_paths:)
          raise NotImplementedError
        end
      end
    end
  end
end
