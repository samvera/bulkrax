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
  #
  # @see .entry_for
  module EntrySpecHelper
    ##
    # @api public
    # @since v5.0.1
    #
    # The purpose of this method is encapsulate the logic of creating the appropriate
    # {Bulkrax::Entry} object based on the given data, identifier, and parser_class_name.  Due to
    # the different means of instantiation of {Bulkrax::Entry} subclasses, there are several
    # optional parameters.
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
    # @param type [Sybmol] The type of entry (e.g. :entry, :collection, :file_set) for testing.
    # @param options [Hash<Symbol,Object>] these are to be passed along into the instantiation of
    #        the various classes.
    # @option options [String] importer_name (Optional) The name of the test importer.  One will be
    #         auto-assigned if unprovided.
    # @option options [String] importer_admin_set_id (Optional) The ID of an admin set to deposit
    #         into.  One will be auto-assigned if unprovided.  And this admin set does not need to
    #         be persisted nor exist.  It is simply a required parameter for instantiating an
    #         importer.
    # @option options [User] user (Optional) The user who is performing the import.  One will be
    #         auto-assigned if unprovided.  The user does not need to be persisted.  It is simply a
    #         required parameter for instantiating an importer
    # @option options [Integer] limit (Optional) You really shouldn't need to set this, but for
    #         completeness it is provided.
    # @option options [Hash<String, Object>] importer_field_mappings Each parser class may require
    #         different field mappings.  See the given examples for more details.
    #
    # @return [Bulkrax::Entry] a subclass of {Bulkrax::Entry} based on the application's
    #         configuration.  It would behoove you to write a spec regarding the returned entry's
    #         class.
    #
    # @example
    #   entry = Bulkrax::EntrySpecHelper.entry_for(
    #     data: { source_identifier: "123", title: "Hello World" },
    #     parser_class_name: "Bulkrax::CsvParser",
    #     importer_field_mappings: { 'import_file_path' => "path/to/file.csv" }
    #   )
    #
    # @note In the case of the Bulkrax::CsvParser, the :data keyword is a Hash, where the keys are
    #       the column name of the CSV you're importing.  The 'import_file_path' is a path to a CSV
    #       file.  That CSV's columns does not need to match the :data's keys, though there may be
    #       required headers on that CSV based on the parser implementation.
    #
    # @example
    #   entry = Bulkrax::EntrySpecHelper.entry_for(
    #     identifier: identifier,
    #     data: File.read("/path/to/some/file.xml"),
    #     parser_class_name: "Bulkrax::OaiDcParser",
    #     parser_fields: { "base_url" => "http://oai.adventistdigitallibrary.org/OAI-script" }
    #   )
    #
    # @note In the case of an OaiParser, the :data keyword should be a String.  And you'll need to
    #       provide a :parser_fields with a "base_url".
    def self.entry_for(data:, identifier:, parser_class_name:, type: :entry, **options)
      importer = importer_for(parser_class_name: parser_class_name, **options)
      entry_type_method_name = ENTRY_TYPE_TO_METHOD_NAME_MAP.fetch(type)
      entry_class = importer.parser.public_send(entry_type_method_name)

      # Using an instance of the entry_class to dispatch to different
      entry_for_dispatch = entry_class.new

      # Using the {is_a?} test we get the benefit of inspecting an object's inheritance path
      # (e.g. ancestry).  The logic, as implemented, also provides a mechanism for folks in their
      # applications to add a {class_name_entry_for}; something that I suspect isn't likely
      # but given the wide variety of underlying needs I could see happening and I want to encourage
      # patterned thinking to fold that different build method into this structure.
      key = entry_class_to_symbol_map.keys.detect { |class_name| entry_for_dispatch.is_a?(class_name.constantize) }

      # Yes, we'll raise an error if we didn't find a corresponding key.  And that's okay.
      symbol = entry_class_to_symbol_map.fetch(key)

      send("build_#{symbol}_entry_for",
           importer: importer,
           identifier: identifier,
           entry_class: entry_class,
           data: data,
           **options)
    end

    ##
    # @api public
    #
    # @param parser_class_name [String]
    # @param parser_fields [Hash<String,Hash>]
    #
    # @return [Bulkrax::Exporter]
    def self.exporter_for(parser_class_name:, parser_fields: {}, **options)
      Bulkrax::Exporter.new(
        name: options.fetch(:exporter_name, "Test importer for identifier"),
        user: options.fetch(:exporter_user, User.new(email: "hello@world.com")),
        limit: options.fetch(:exporter_limit, 1),
        parser_klass: parser_class_name,
        field_mapping: options.fetch(:exporter_field_mappings) { Bulkrax.field_mappings.fetch(parser_class_name) },
        parser_fields: parser_fields
      )
    end

    ENTRY_TYPE_TO_METHOD_NAME_MAP = {
      entry: :entry_class,
      collection: :collection_entry_class,
      file_set: :file_set_entry_class
    }.freeze

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
      ).tap do |importer|
        # Why are we saving the importer and a run?  We might want to delve deeper into the call
        # stack.  See https://github.com/scientist-softserv/adventist-dl/pull/266
        importer.save!
        # Later on, we might to want a current run
        importer.importer_runs.create!
      end
    end
    private_class_method :importer_for

    def self.build_csv_entry_for(importer:, data:, identifier:, entry_class:, **_options)
      entry_class.new(
        importerexporter: importer,
        identifier: identifier,
        raw_metadata: data
      )
    end
    private_class_method :build_csv_entry_for

    def self.build_oai_entry_for(importer:, data:, identifier:, entry_class:, **options)
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

      entry_class.new(
        raw_record: raw_record,
        importerexporter: importer,
        identifier: identifier,
        raw_metadata: raw_metadata
      )
    end
    private_class_method :build_oai_entry_for

    def self.build_xml_entry_for(importer:, data:, identifier:, entry_class:, **options)
      raw_metadata = {
        importer.parser.source_identifier.to_s => identifier,
        "data" => data,
        "collections" => options.fetch(:raw_metadata_collections, []),
        "children" => options.fetch(:raw_metadata_children, [])
      }

      entry_class.new(
        importerexporter: importer,
        identifier: identifier,
        raw_metadata: raw_metadata
      )
    end
    private_class_method :build_xml_entry_for
  end
end
