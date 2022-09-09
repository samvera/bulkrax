# frozen_string_literal: true

require "bulkrax/version"
require "bulkrax/engine"
require 'active_support/all'

module Bulkrax
  class << self
    mattr_accessor :api_definition,
                   :default_field_mapping,
                   :default_work_type,
                   :export_path,
                   :field_mappings,
                   :fill_in_blank_source_identifiers,
                   :generated_metadata_mapping,
                   :import_path,
                   :multi_value_element_join_on,
                   :multi_value_element_split_on,
                   :parsers,
                   :qa_controlled_properties,
                   :related_children_field_mapping,
                   :related_parents_field_mapping,
                   :removed_image_path,
                   :reserved_properties,
                   :server_name

    self.parsers = [
      { name: "OAI - Dublin Core", class_name: "Bulkrax::OaiDcParser", partial: "oai_fields" },
      { name: "OAI - Qualified Dublin Core", class_name: "Bulkrax::OaiQualifiedDcParser", partial: "oai_fields" },
      { name: "CSV - Comma Separated Values", class_name: "Bulkrax::CsvParser", partial: "csv_fields" },
      { name: "Bagit", class_name: "Bulkrax::BagitParser", partial: "bagit_fields" },
      { name: "XML", class_name: "Bulkrax::XmlParser", partial: "xml_fields" }
    ]

    self.import_path = Bulkrax.import_path || 'tmp/imports'
    self.export_path = Bulkrax.export_path || 'tmp/exports'
    self.removed_image_path = Bulkrax::Engine.root.join('spec', 'fixtures', 'removed.png').to_s
    self.server_name = 'bulkrax@example.com'

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
        field.to_s =>
        {
          from: [field.to_s],
          split: false,
          parsed: Bulkrax::ApplicationMatcher.method_defined?("parse_#{field}"),
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

    # List of Questioning Authority properties that are controlled via YAML files in
    # the config/authorities/ directory. For example, the :rights_statement property
    # is controlled by the active terms in config/authorities/rights_statements.yml
    self.qa_controlled_properties = %w[rights_statement license]
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

  DEFAULT_MULTI_VALUE_ELEMENT_JOIN_ON = ' | '
  # Specify the delimiter for joining an attribute's multi-value array into a string.
  #
  # @note the specific delimeter should likely be present in the multi_value_element_split_on
  #       expression.
  def self.multi_value_element_join_on
    @multi_value_element_join_on ||= DEFAULT_MULTI_VALUE_ELEMENT_JOIN_ON
  end

  DEFAULT_MULTI_VALUE_ELEMENT_SPLIT_ON = /\s*[:;|]\s*/.freeze
  # @return [RegexClass] the regular express to use to "split" an attribute's values.  If set to
  # `true` use the DEFAULT_MULTI_VALUE_ELEMENT_JOIN_ON.
  #
  # @note The "true" value is to preserve backwards compatibility.
  # @see DEFAULT_MULTI_VALUE_ELEMENT_JOIN_ON
  def self.multi_value_element_split_on
    if @multi_value_element_join_on.is_a?(TrueClass)
      DEFAULT_MULTI_VALUE_ELEMENT_SPLIT_ON
    else
      @multi_value_element_split_on ||= DEFAULT_MULTI_VALUE_ELEMENT_SPLIT_ON
    end
  end

  # this function maps the vars from your app into your engine
  def self.setup
    yield self
  end
end
