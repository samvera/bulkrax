# frozen_string_literal: true

require 'oai'
require 'xml/libxml'

module Bulkrax
  ##
  # The purpose of this module is to provide some testing facilities for those that include the
  # Bulkrax gem in their application.
  #
  # This module came about through a desire to expose a quick means of vetting the accuracy of the
  # different parsers.
  module EntrySpecHelper
    ##
    # @api public
    # @since v5.0.1
    #
    # The purpose of this method is encapsulate the logic of creating the appropriate Bulkrax::Entry
    # object based on the given data, identifier, and parser_class_name.
    #
    # From that entry, you should be able to test how {Bulkrax::Entry#build_metadata} populates the
    # {Bulkrax::Entry#parsed_metadata} variable.  Other uses may emerge.
    #
    # @param data [Object] the data that we use to populate the raw metadata.  Due to implementation
    #        details of each entry, the data will be of different formats.
    #
    # @param identifier [String, Integer] The identifier of the entry.  This might also be found in
    #        the metadata of the entry, but for instantiation purposes we need this value.
    # @param parser_class_name [String] The name of the parser class you're wanting to test.
    # @param options [Hash<Symbol,Object>] these are to be passed along into the instantiation of
    #        the various classes.  See implementation details.
    #
    # @return [Bulkrax::Entry]
    def self.entry_for(data:, identifier:, parser_class_name:, **options)
      importer = importer_for(parser_class_name: parser_class_name, **options)

      # Using an instance of the entry_class to dispatch to different
      entry_for_dispatch = importer.parser.entry_class.new

      # Using the {is_a?} test we get the benefit of inspecting an object's inheritance path
      # (e.g. ancestry).  The logic, as implemented, also provides a mechanism for folks in their
      # applications to add a {class_name_entry_for}; something that I suspect isn't likely
      # but given the wide variety of underlying needs I could see happening and I want to encourage
      # patterned thinking to fold that different build method into this structure.
      key = entry_class_to_symbol_map.keys.detect { |class_name| entry_for_dispatch.is_a?(class_name.constantize) }

      # Yes, we'll raise an error if we didn't find a corresponding key.  And that's okay.
      symbol = entry_class_to_symbol_map.fetch(key)

      send("build_#{symbol}_entry_for", importer: importer, identifier: identifier, data: data, **options)
    end

    DEFAULT_ENTRY_CLASS_TO_SYMBOL_MAP = {
      'Bulkrax::OaiEntry' => :oai,
      'Bulkrax::XmlEntry' => :xml,
      'Bulkrax::CsvEntry' => :csv
    }.freeze

    # Present implementations of entry classes tend to inherit from the below listed class names.
    # We're not looking to register all descendents of the {Bulkrax::Entry} class, but instead find
    # the ancestor where there is significant deviation.
    def self.entry_class_to_symbol_map
      @entry_class_to_symbol_map || DEFAULT_ENTRY_CLASS_TO_SYMBOL_MAP
    end

    def self.entry_class_to_symbol_map=(value)
      @entry_class_to_symbol_map = value
    end

    def self.importer_for(parser_class_name:, parser_fields: {}, **options)
      # Ideally, we could pass in the field_mapping.  However, there is logic that ignores the
      # parser's field_mapping and directly asks for Bulkrax's field_mapping (e.g. model_mapping
      # method).
      Rails.logger.warn("You passed :importer_field_mapping as an option.  This may not fully work as desired.") if options.key?(:importer_field_mapping)
      Bulkrax::Importer.new(
        name: options.fetch(:importer_name, "Test importer for identifier"),
        admin_set_id: options.fetch(:importer_admin_set_id, "admin_set/default"),
        user: options.fetch(:importer_user, User.new(email: "hello@world.com")),
        limit: options.fetch(:importer_limits, 1),
        parser_klass: parser_class_name,
        field_mapping: options.fetch(:importer_field_mappings) { Bulkrax.field_mappings.fetch(parser_class_name) },
        parser_fields: parser_fields
      )
    end
    private_class_method :importer_for

    ##
    # @api private
    #
    # @param data [Hash<Symbol,String>] we're expecting a hash with keys that are symbols and then
    #        values that are strings.
    #
    # @return [Bulkrax::CsvEntry]
    #
    # @note As a foible of this implementation, you'll need to include along a CSV to establish the
    #       columns that you'll parse (e.g. the first row
    def self.build_csv_entry_for(importer:, data:, identifier:, **_options)
      importer.parser.entry_class.new(
        importerexporter: importer,
        identifier: identifier,
        raw_metadata: data
      )
    end

    ##
    # @api private
    #
    # @param data [String] we're expecting a string that is well-formed XML for OAI parsing.
    #
    # @return [Bulkrax::OaiEntry]
    def self.build_oai_entry_for(importer:, data:, identifier:, **options)
      # The raw record assumes we take the XML data, parse it and then send that to the
      # OAI::GetRecordResponse object.
      doc = XML::Parser.string(data)
      raw_record = OAI::GetRecordResponse.new(doc.parse)

      raw_metadata = {
        importer.parser.source_identifier.to_s => identifier,
        "data" => data,
        "collections" => options.fetch(:raw_metadata_collections, []),
        "children" => options.fetch(:raw_metadata_children, [])
      }

      importer.parser.entry_class.new(
        raw_record: raw_record,
        importerexporter: importer,
        identifier: identifier,
        raw_metadata: raw_metadata
      )
    end

    ##
    # @api private
    #
    # @param data [String] we're expecting a string that is well-formed XML.
    #
    # @return [Bulkrax::XmlEntry]
    def self.build_xml_entry_for(importer:, data:, identifier:, **options)
      raw_metadata = {
        importer.parser.source_identifier.to_s => identifier,
        "data" => data,
        "collections" => options.fetch(:raw_metadata_collections, []),
        "children" => options.fetch(:raw_metadata_children, [])
      }

      importer.parser.entry_class.new(
        importerexporter: importer,
        identifier: identifier,
        raw_metadata: raw_metadata
      )
    end
  end
end
