require "bulkrax/engine"

module Bulkrax
  class << self
    mattr_accessor :parsers, :system_identifier_field, :default_field_mapping, :reserved_properties, :field_mappings

    self.parsers = [
      { name: "OAI - Dublin Core", class_name: "Bulkrax::OaiDcParser", partial: "oai_fields" },
      { name: "OAI - Qualified Dublin Core", class_name: "Bulkrax::OaiQualifiedDcParser", partial: "oai_fields" },
      { name: "CSV - Comma Separated Values", class_name: "Bulkrax::CsvParser", partial: "csv_fields" }
    ]

    self.system_identifier_field = "source"

    # Hash of Generic field_mappings for use in the view
    # There must be one field_mappings hash per view parial
    # Based on Hyrax CoreMetadata && BasicMetadata
    # Override at appliation level to change
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
      }
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

  # this function maps the vars from your app into your engine
  def self.setup
    yield self
  end
end
