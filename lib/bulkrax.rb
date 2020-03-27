# frozen_string_literal: true

require "bulkrax/engine"
require 'active_support/all'

module Bulkrax
  class << self
    mattr_accessor :parsers,
                   :system_identifier_field,
                   :default_work_type,
                   :default_field_mapping,
                   :source_identifier_field_mapping,
                   :collection_field_mapping,
                   :parent_child_field_mapping,
                   :reserved_properties,
                   :field_mappings,
                   :import_path,
                   :export_path,
                   :server_name,
                   :api_definition

    self.parsers = [
      { name: "OAI - Dublin Core", class_name: "Bulkrax::OaiDcParser", partial: "oai_fields" },
      { name: "OAI - Qualified Dublin Core", class_name: "Bulkrax::OaiQualifiedDcParser", partial: "oai_fields" },
      { name: "CSV - Comma Separated Values", class_name: "Bulkrax::CsvParser", partial: "csv_fields" },
      { name: "Bagit", class_name: "Bulkrax::BagitParser", partial: "bagit_fields" },
      { name: "XML", class_name: "Bulkrax::XmlParser", partial: "xml_fields" }
    ]

    self.system_identifier_field = "source"
    self.import_path = 'tmp/imports'
    self.export_path = 'tmp/exports'
    self.server_name = 'bulkrax@example.com'

    # Field_mapping for establishing a source_identifier to use as the unique identifier for the entry
    # This value IS NOT used for OAI, so setting the OAI Entries here will have no effect
    # The mapping is supplied per Entry, provide the full class name as a string, eg. 'Bulkrax::CsvEntry'
    # The default value for CSV is source_identifier, for RDF it is the subject
    self.source_identifier_field_mapping = {}

    # @todo, merge parent_child_field_mapping and collection_field_mapping into field_mappings,
    # or make them settable per import some other way.

    # Field_mapping for establishing a parent-child relationship (FROM parent TO child)
    # This can be a Collection to Work, or Work to Work relationship
    # This value IS NOT used for OAI, so setting the OAI Entries here will have no effect
    # The mapping is supplied per Entry, provide the full class name as a string, eg. 'Bulkrax::CsvEntry'
    # Example:
    #   {
    #     'Bulkrax::RdfEntry'  => 'http://opaquenamespace.org/ns/contents',
    #     'Bulkrax::CsvEntry'  => 'children'
    #   }
    # By default no parent-child relationships are added
    self.parent_child_field_mapping = {}

    # Field_mapping for establishing a collection relationship (FROM work TO collection)
    # This value IS NOT used for OAI, so setting the OAI Entries here will have no effect
    # The mapping is supplied per Entry, provide the full class name as a string, eg. 'Bulkrax::CsvEntry'
    # The default value for CSV is collection
    self.collection_field_mapping = {}

    # Hash of Generic field_mappings for use in the view
    # There must be one field_mappings hash per view parial
    # Based on Hyrax CoreMetadata && BasicMetadata
    # Override at application level to change
    self.field_mappings = {
      "Bulkrax::OaiDcParser" => {
        "contributor" => { from: ["contributor"] },
        # no appropriate mapping for coverage (based_near needs id)
        #  ""=>{:from=>["coverage"]},
        "creator" => { from: ["creator"] },
        "date_created" => { from: ["date"] },
        "description" => { from: ["description"] },
        # no appropriate mapping for format
        # ""=>{:from=>["format"]},
        "identifier" => { from: ["identifier"] },
        "language" => { from: ["language"], parsed: true },
        "publisher" => { from: ["publisher"] },
        "related_url" => { from: ["relation"] },
        "rights_statement" => { from: ["rights"] },
        "source" => { from: ["source"] },
        "subject" => { from: ["subject"], parsed: true },
        "title" => { from: ["title"] },
        "resource_type" => { from: ["type"], parsed: true },
        "remote_files" => { from: ["thumbnail_url"], parsed: true }
      },
      "Bulkrax::OaiQualifiedDcParser" => {
        "abstract" => { from: ["abstract"] },
        "alternative_title" => { from: ["alternative"] },
        "bibliographic_citation" => { from: ["bibliographicCitation"] },
        "contributor" => { from: ["contributor"] },
        "creator" => { from: ["creator"] },
        "date_created" => { from: ["created"] },
        "description" => { from: ["description"] },
        "language" => { from: ["language"] },
        "license" => { from: ["license"] },
        "publisher" => { from: ["publisher"] },
        "related_url" => { from: ["relation"] },
        "rights_holder" => { from: ["rightsHolder"] },
        "rights_statement" => { from: ["rights"] },
        "source" => { from: ["source"] },
        "subject" => { from: ["subject"], parsed: true },
        "title" => { from: ["title"] },
        "resource_type" => { from: ["type"], parsed: true },
        "remote_files" => { from: ["thumbnail_url"], parsed: true }
      },
      # When empty, a default_field_mapping will be generated
      "Bulkrax::CsvParser" => {},
      'Bulkrax::BagitParser' => {},
      'Bulkrax::XmlParser' => {}
    }

    # Lambda to set the default field mapping
    self.default_field_mapping = lambda do |field|
      return if field.blank?
      {
        field =>
        {
          from: [field],
          split: false,
          parsed: false,
          if: nil,
          excluded: false
        }
      }
    end

    # Properties that should not be used in imports. They are reserved for use by Hyrax.
    self.reserved_properties = %w[
      create_date
      modified_date
      date_modified
      date_uploaded
      depositor
      arkivo_checksum
      has_model
      head
      label
      import_url
      on_behalf_of
      proxy_depositor
      owner
      state
      tail
      original_url
      relative_path
    ]
  end

  def self.api_definition
    @api_definition ||= ActiveSupport::HashWithIndifferentAccess.new(
      YAML.safe_load(
        ERB.new(
          File.read(Rails.root.join('config', 'bulkrax_api.yml'))
        ).result
      )
    )
  end

  # this function maps the vars from your app into your engine
  def self.setup
    yield self
  end
end
