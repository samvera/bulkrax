# frozen_string_literal: true

module Bulkrax
  class FactoryClassFinder
    ##
    # The v6.0.0 default coercer.  Responsible for converting a factory class name to a constant.
    module DefaultCoercer
      ##
      # @param name [String]
      # @return [Class] when the name is a coercible constant.
      # @raise [NameError] when the name is not coercible to a constant.
      def self.call(name)
        name.constantize
      end
    end

    ##
    # A name coercer that favors classes that end with "Resource" but will attempt to fallback to
    # those that don't.
    module ValkyrieMigrationCoercer
      SUFFIX = "Resource"

      ##
      # @param name [String]
      # @param suffix [String] the suffix we use for a naming convention.
      #
      # @return [Class] when the name is a coercible constant.
      # @raise [NameError] when the name is not coercible to a constant.
      def self.call(name, suffix: SUFFIX)
        if name.end_with?(suffix)
          name.constantize
        elsif name == "FileSet"
          Bulkrax.file_model_class
        else
          begin
            "#{name}#{suffix}".constantize
          rescue NameError
            name.constantize
          end
        end
      end
    end

    ##
    # @param entry [Bulkrax::Entry]
    # @return [Class]
    def self.find(entry:, coercer: Bulkrax.factory_class_name_coercer || DefaultCoercer)
      new(entry: entry, coercer: coercer).find
    end

    ##
    # @param name [String] a model name as a sheet or export spells it
    # @return [Class] the class import creates for that name
    # @return [Nil] when no class matches the name
    def self.resolve(name, coercer: Bulkrax.factory_class_name_coercer || DefaultCoercer)
      name = normalize_class_name(name)
      configured_model_class_for(name) || coercer.call(name)
    rescue NameError
      nil
    end

    # Sheets and exports spell file set and collection models either way, and
    # the factories and CsvEntry pick those paths by exact comparison with the
    # configured class.
    def self.configured_model_class_for(name)
      return Bulkrax.file_model_class if Bulkrax.file_model_name?(name)
      Bulkrax.collection_model_class if Bulkrax.collection_model_name?(name)
    end

    ##
    # Normalize a class name string to proper format
    # @param name [String] the class name to normalize
    # @return [String] the normalized class name
    def self.normalize_class_name(name)
      name = name.to_s
      name = name.tr(' ', '_')
      name = name.downcase if name.match?(/[-_]/)
      name.camelcase
    end
    private_class_method :configured_model_class_for, :normalize_class_name

    def initialize(entry:, coercer:)
      @entry = entry
      @coercer = coercer
    end
    attr_reader :entry, :coercer

    ##
    # @return [Class] when we are able to derive the class based on the {#name}.
    # @return [Nil] when we encounter errors with constantizing the {#name}.
    # @see #name
    def find
      self.class.resolve(name, coercer: coercer)
    rescue
      entry.default_work_type.constantize
    end

    private

    ##
    # @api private
    # @return [String]
    def name
      # Try each strategy in order until one returns a value
      find_factory_class_name || entry.default_work_type
    rescue
      entry.default_work_type
    end

    ##
    # Try each strategy in sequence to find a factory class name
    # @return [String, nil] the factory class name or nil if none found
    def find_factory_class_name
      prioritized_strategies = [
        :model_from_parsed_metadata,
        :work_type_from_parsed_metadata,
        :model_from_raw_metadata,
        :model_from_mapped_field
      ]

      # Return the first non-nil result
      prioritized_strategies.each do |strategy|
        result = send(strategy)
        return result if result.present?
      end

      nil
    end

    def model_from_parsed_metadata
      Array.wrap(entry.parsed_metadata['model']).first if entry.parsed_metadata&.[]('model').present?
    end

    def work_type_from_parsed_metadata
      Array.wrap(entry.parsed_metadata['work_type']).first if entry.importerexporter&.mapping&.[]('work_type').present?
    end

    def model_from_raw_metadata
      Array.wrap(entry.raw_metadata&.[]('model'))&.first if entry.raw_metadata&.[]('model').present?
    end

    def model_from_mapped_field
      return nil unless entry.parser.model_field_mappings.any? { |field| entry.raw_metadata&.[](field).present? }
      field = entry.parser.model_field_mappings.find { |f| entry.raw_metadata&.[](f).present? }
      Array.wrap(entry.raw_metadata[field]).first
    end
  end
end
