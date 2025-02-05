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
          Bulkrax.file_model_class.to_s.constantize
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
      coercer.call(name)
    rescue NameError
      nil
    rescue
      entry.default_work_type.constantize
    end

    ##
    # @api private
    # @return [String]
    def name
      fc = if entry.parsed_metadata&.[]('model').present?
             Array.wrap(entry.parsed_metadata['model']).first
           elsif entry.importerexporter&.mapping&.[]('work_type').present?
             # Because of delegation's nil guard, we're reaching rather far into the implementation
             # details.
             Array.wrap(entry.parsed_metadata['work_type']).first
           else
             entry.default_work_type
           end

      # Let's coerce this into the right shape; we're not mutating the string because it might well
      # be frozen.
      fc = fc.tr(' ', '_')
      fc = fc.downcase if fc.match?(/[-_]/)
      fc.camelcase
    rescue
      entry.default_work_type
    end
  end
end
