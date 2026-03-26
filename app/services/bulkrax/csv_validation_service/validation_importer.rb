# frozen_string_literal: true

module Bulkrax
  class CsvValidationService
    ##
    # A null-object stand-in for Bulkrax::Importer used when the CsvParser is
    # run in validation mode.
    #
    # It satisfies the interface that ApplicationParser and CsvParser delegate to
    # `importerexporter` during the records / build_records / import_fields path,
    # without touching ActiveRecord, triggering callbacks, or causing side-effects.
    #
    # Any method called by the parser that is not implemented here will raise
    # NoMethodError immediately, making interface gaps visible during testing.
    #
    class ValidationImporter
      include Bulkrax::ImporterExporterBehavior

      attr_reader :parser_fields, :field_mapping

      def initialize(parser_fields:, field_mapping: {})
        @parser_fields = parser_fields
        @field_mapping = field_mapping
      end

      # Required by ApplicationParser#perform_method and the delegate list.
      def validate_only
        false
      end

      # Required by CsvParser#records (only_updates branch).
      def only_updates
        false
      end

      # Required by ApplicationParser#create_objects (not called in validation,
      # but referenced via the delegate list — return a safe default).
      def remove_and_rerun
        false
      end

      # Required by ApplicationParser#required_elements.
      # Returns an empty hash so source_identifier falls back to the default.
      def mapping
        {}
      end
    end
  end
end
