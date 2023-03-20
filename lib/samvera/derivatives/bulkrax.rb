# frozen_string_literal: true

module Samvera
  module Derivatives
    module Bulkrax
      ##
      # Responsible for locating a derivative associated with a Bulkrax import.
      #
      # @see .locate
      class FileLocator
        ##
        # @param file_set [FileSet]
        # @param derivative_type [#to_sym]
        #
        # @return [FalseClass] when no {Bulkrax::EntryDerivative} is found for the given parameters
        #         or when we encounter errors retrieving that derivative.
        # @return [String] the full path to the derivative described by the corresponding
        #         {Bulkrax::EntryDerivative}
        #
        # @see Samvera::Derivatives::FileLocator::Strategy
        #
        # @note If there are multiple {Bulkrax::EntryDerivative} objects for the associated
        #       {FileSet}, process the most recently created one.
        def self.locate(file_set:, derivative_type:, *)
          # Find the corresponding Bulkrax::EntryDerivative for the given :derivative_type and :file_set
          #
          # Return false if no Bulkrax::EntryDerivative is found
          #
          # Otherwise
          #
          # - determine the resuling path to the derivative.  If it exists, return that path.
          # - If it does not exist attempt to fetch the remote URL and write it to the resulting path.
          # - Rescue fetch errors by:
          #   ...reporting an exception
          #   and
          #   ...returning false (e.g. we'll run the local derivatives)
        end
      end

      class FileApplicator
        ##
        # @param file_set [FileSet]
        # @param derivative_type [#to_sym]
        # @param from_location [String]
        #
        # Copy the from_location to a to location on the file system, following the pattern
        # established in {Hyrax::FileSetDerivativesService}
        #
        # @see Samvera::Derivatives::FileLocator::Strategy
        def self.apply!(file_set:, derivative_type:, from_location:)
          new(file_set: file_set, derivative_type: derivative_type, from_location: from_location)
        end

        # Why not set a default?  Because the ::Hyrax may not be defined.  This setup allows for a
        # lazier definition.
        class_attribute :derivative_path_service, instance_accessor: false

        ##
        # @param file_set [FileSet]
        # @param derivative_type [#to_sym]
        # @param from_location [String]
        # @param derivative_path_service [#derivative_path_for_reference]
        def initialize(file_set:, derivative_type:, from_location:, derivative_path_service: default_derivative_path_service)
          @file_set = file_set
          @derivative_type = derivative_type
          @from_location = from_location
          @derivative_path_service = derivative_path_service
        end

        attr_reader :file_set, :derivative_type, :from_location, :derivative_path_service
        private :file_set, :derivative_type, :from_location, :derivative_path_service

        private

        def process_apply!
          to_location = derivative_path_service.derivative_path_for_reference(file_set, extension)
          to_dir = File.dirname(to_location)
          FileUtils.mkdir_p(to_dir) unless File.directory?(to_dir)
          FileUtils.cp(from_location, to_location)
        end

        def default_derivative_path_service
          self.class.default_derivative_path_service || ::Hyrax::DerivativePath
        end

        def extension
          # TODO: How do we determine that based on derivative type?
          raise NotImplementedError
        end
      end
    end
  end
end
