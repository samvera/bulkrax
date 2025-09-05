# frozen_string_literal: true

module Bulkrax
  # Custom error class for collections_created?
  class CollectionsCreatedError < RuntimeError; end
  class OAIError < RuntimeError; end

  class Entry < ApplicationRecord
    include Bulkrax::HasMatchers
    include Bulkrax::ImportBehavior
    self.class_attribute :default_work_type, default: Bulkrax.default_work_type

    include Bulkrax::ExportBehavior
    include Bulkrax::StatusInfo
    include Bulkrax::HasLocalProcessing

    belongs_to :importerexporter, polymorphic: true
    alias importer importerexporter
    alias exporter importerexporter

    if Rails.version < '7.1'
      serialize :parsed_metadata, Bulkrax::NormalizedJson
      # Do not serialize raw_metadata as so we can support xml or other formats
      serialize :collection_ids, Array
    else
      serialize :parsed_metadata, coder: Bulkrax::NormalizedJson
      # Do not serialize raw_metadata as so we can support xml or other formats
      serialize :collection_ids, coder: YAML, type: Array
    end

    paginates_per 5

    attr_accessor :all_attrs

    delegate :parser,
      :mapping,
      :replace_files,
      :update_files,
      :keys_without_numbers,
      :key_without_numbers,
      to: :importerexporter

    delegate :client,
      :collection_name,
      :user,
      :generated_metadata_mapping,
      :related_parents_raw_mapping,
      :related_parents_parsed_mapping,
      :related_children_raw_mapping,
      :related_children_parsed_mapping,
      to: :parser

    # Retrieve fields from the file
    # @param data - the source data
    # @return Array
    def self.fields_from_data(_data)
      raise StandardError, 'Not Implemented'
    end

    # Read the data from the supplied path
    # @param path - path to the data file
    # @return the data from the file
    def self.read_data(_path)
      raise StandardError, 'Not Implemented'
    end

    # Returns formatted data from the given file for a single Entry
    # @param data - the data from the metadata file
    # @param path - the path to the metadata file (used by some entries to get the file_paths for import)
    # @return Hash containing the data (the entry build_metadata method will know what to expect in the hash)
    def self.data_for_entry(_data, _source_id, _parser)
      raise StandardError, 'Not Implemented'
    end

    def source_identifier
      parser&.source_identifier&.to_s || 'source_identifier'
    end

    def work_identifier
      parser&.work_identifier&.to_s || 'source'
    end

    # Returns field_mapping hash based on whether or not generated metadata should be included
    def fetch_field_mapping
      return self.mapping if importerexporter.generated_metadata

      self.mapping.each do |key, value|
        self.mapping.delete(key) if value[generated_metadata_mapping]
      end
    end

    def self.parent_field(parser)
      parser.related_parents_parsed_mapping
    end

    def build
      return if type.nil?
      self.save if self.new_record? # must be saved for statuses

      return build_for_importer if importer?
      return build_for_exporter if exporter?
    end

    def importer?
      self.importerexporter_type == 'Bulkrax::Importer'
    end

    def exporter?
      self.importerexporter_type == 'Bulkrax::Exporter'
    end

    def last_run
      self.importerexporter&.last_run
    end

    def find_collection(collection_identifier)
      Bulkrax.object_factory.search_by_property(
        klass: Bulkrax.collection_model_class,
        value: collection_identifier,
        search_field: work_identifier,
        name_field: work_identifier,
        verify_property: true
      )
    end
  end
end
