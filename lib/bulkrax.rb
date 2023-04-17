# frozen_string_literal: true

require "bulkrax/version"
require "bulkrax/engine"
require 'active_support/all'

# rubocop:disable Metrics/ModuleLength
module Bulkrax
  extend self # rubocop:disable Style/ModuleFunction
  extend Forwardable

  ##
  # @api public
  class Configuration
    attr_accessor :api_definition,
                  :curation_concerns,
                  :default_field_mapping,
                  :default_work_type,
                  :export_path,
                  :field_mappings,
                  :file_model_class,
                  :fill_in_blank_source_identifiers,
                  :generated_metadata_mapping,
                  :import_path,
                  :multi_value_element_join_on,
                  :multi_value_element_split_on,
                  :object_factory,
                  :parsers,
                  :qa_controlled_properties,
                  :related_children_field_mapping,
                  :related_parents_field_mapping,
                  :relationship_job_class,
                  :removed_image_path,
                  :required_elements,
                  :reserved_properties,
                  :server_name
  end

  def config
    @config ||= Configuration.new
    yield @config if block_given?
    @config
  end
  alias setup config

  def_delegators :@config,
                 :api_definition,
                 :api_definition=,
                 :curation_concerns,
                 :curation_concerns=,
                 :default_field_mapping,
                 :default_field_mapping=,
                 :default_work_type,
                 :default_work_type=,
                 :export_path,
                 :export_path=,
                 :field_mappings,
                 :field_mappings=,
                 :file_model_class,
                 :file_model_class=,
                 :fill_in_blank_source_identifiers,
                 :fill_in_blank_source_identifiers=,
                 :generated_metadata_mapping,
                 :generated_metadata_mapping=,
                 :import_path,
                 :import_path=,
                 :multi_value_element_join_on,
                 :multi_value_element_join_on=,
                 :multi_value_element_split_on,
                 :multi_value_element_split_on=,
                 :object_factory,
                 :object_factory=,
                 :parsers,
                 :parsers=,
                 :qa_controlled_properties,
                 :qa_controlled_properties=,
                 :related_children_field_mapping,
                 :related_children_field_mapping=,
                 :related_parents_field_mapping,
                 :related_parents_field_mapping=,
                 :relationship_job_class,
                 :relationship_job_class=,
                 :removed_image_path,
                 :removed_image_path=,
                 :required_elements,
                 :required_elements=,
                 :reserved_properties,
                 :reserved_properties=,
                 :server_name,
                 :server_name=

  config do |conf|
    conf.parsers = [
      { name: "OAI - Dublin Core", class_name: "Bulkrax::OaiDcParser", partial: "oai_fields" },
      { name: "OAI - Qualified Dublin Core", class_name: "Bulkrax::OaiQualifiedDcParser", partial: "oai_fields" },
      { name: "CSV - Comma Separated Values", class_name: "Bulkrax::CsvParser", partial: "csv_fields" },
      { name: "Bagit", class_name: "Bulkrax::BagitParser", partial: "bagit_fields" },
      { name: "XML", class_name: "Bulkrax::XmlParser", partial: "xml_fields" }
    ]

    conf.import_path = Bulkrax.import_path || 'tmp/imports'
    conf.export_path = Bulkrax.export_path || 'tmp/exports'
    conf.removed_image_path = Bulkrax::Engine.root.join('spec', 'fixtures', 'removed.png').to_s
    conf.server_name = 'bulkrax@example.com'
    conf.relationship_job_class = "Bulkrax::CreateRelationshipsJob"
    conf.required_elements = ['title']

    def conf.curation_concerns
      @curation_concerns ||= defined?(::Hyrax) ? ::Hyrax.config.curation_concerns : []
    end

    def conf.curation_concerns=(val)
      @curation_concerns = val
    end

    def conf.file_model_class
      @file_model_class ||= defined?(::Hyrax) ? ::FileSet : File
    end

    def conf.file_model_class=(val)
      @file_model_class = val
    end

    # Hash of Generic field_mappings for use in the view
    # There must be one field_mappings hash per view partial
    # Based on Hyrax CoreMetadata && BasicMetadata
    # Override at application level to change
    conf.field_mappings = {
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
    conf.default_field_mapping = lambda do |field|
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
    conf.reserved_properties = %w[
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
    conf.qa_controlled_properties = %w[rights_statement license]
  end

  def api_definition
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
  # @note the specific delimiter should likely be present in the multi_value_element_split_on
  #       expression.
  def multi_value_element_join_on
    @multi_value_element_join_on ||= DEFAULT_MULTI_VALUE_ELEMENT_JOIN_ON
  end

  DEFAULT_MULTI_VALUE_ELEMENT_SPLIT_ON = /\s*[:;|]\s*/.freeze
  # @return [RegexClass] the regular express to use to "split" an attribute's values.  If set to
  # `true` use the DEFAULT_MULTI_VALUE_ELEMENT_JOIN_ON.
  #
  # @note The "true" value is to preserve backwards compatibility.
  # @see DEFAULT_MULTI_VALUE_ELEMENT_JOIN_ON
  def multi_value_element_split_on
    if @multi_value_element_join_on.is_a?(TrueClass)
      DEFAULT_MULTI_VALUE_ELEMENT_SPLIT_ON
    else
      @multi_value_element_split_on ||= DEFAULT_MULTI_VALUE_ELEMENT_SPLIT_ON
    end
  end

  # Responsible for stripping hidden characters from the given string.
  #
  # @param value [#to_s]
  # @return [String] with hidden characters removed
  #
  # @see https://github.com/samvera-labs/bulkrax/issues/688
  def normalize_string(value)
    # Removing [Byte Order Mark (BOM)](https://en.wikipedia.org/wiki/Byte_order_mark)
    value.to_s.delete("\xEF\xBB\xBF")
  end

  def fallback_user_for_importer_exporter_processing
    return User.batch_user if defined?(Hyrax) && User.respond_to?(:batch_user)

    raise "We have no fallback user available for Bulkrax.fallback_user_for_importer_exporter_processing"
  end

  # This class confirms to the Active::Support.serialize interface.  It's job is to ensure that we
  # don't have keys with the tricksy Byte Order Mark character.
  #
  # @see https://api.rubyonrails.org/classes/ActiveRecord/AttributeMethods/Serialization/ClassMethods.html#method-i-serialize
  class NormalizedJson
    def self.normalize_keys(hash)
      return hash unless hash.respond_to?(:each_pair)
      returning_value = {}
      hash.each_pair do |key, value|
        returning_value[Bulkrax.normalize_string(key)] = value
      end
      returning_value
    end

    # When we write the serialized data to the database, we "dump" the value into that database
    # column.
    def self.dump(value)
      JSON.dump(normalize_keys(value))
    end

    # When we load the serialized data from the database, we pass the database's value into "load"
    # function.
    #
    # rubocop:disable Security/JSONLoad
    def self.load(string)
      normalize_keys(JSON.load(string))
    end
    # rubocop:enable Security/JSONLoad
  end
end
# rubocop:disable Metrics/ModuleLength
