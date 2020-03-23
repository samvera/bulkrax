# frozen_string_literal: true

module Bulkrax
  # Custom error class for collections_created?
  class CollectionsCreatedError < RuntimeError; end
  class OAIError < RuntimeError; end
  class Entry < ApplicationRecord
    include Bulkrax::HasMatchers
    include Bulkrax::ImportBehavior
    include Bulkrax::ExportBehavior
    include Bulkrax::Status
    include Bulkrax::HasLocalProcessing

    belongs_to :importerexporter, polymorphic: true
    serialize :parsed_metadata, JSON
    # Do not serialize raw_metadata as so we can support xml or other formats
    serialize :collection_ids, Array
    serialize :last_error, JSON

    paginates_per 5

    attr_accessor :all_attrs

    delegate :parser, :mapping, :replace_files, to: :importerexporter

    delegate :client,
             :collection_name,
             :user,
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
    def self.data_for_entry(_data)
      raise StandardError, 'Not Implemented'
    end

    def self.source_identifier_field
      raise "Source identifier must be configured for #{self}" if Bulkrax.source_identifier_field_mapping[self.to_s].blank?
      Bulkrax.source_identifier_field_mapping[self.to_s]
    end

    def self.collection_field
      Bulkrax.collection_field_mapping[self.to_s]
    end

    def self.children_field
      Bulkrax.parent_child_field_mapping[self.to_s]
    end

    def build
      return if type.nil?
      return build_for_importer if importer?
      return build_for_exporter if exporter?
    end

    def importer?
      self.importerexporter_type == 'Bulkrax::Importer'
    end

    def exporter?
      self.importerexporter_type == 'Bulkrax::Exporter'
    end

    def valid_system_id(model_class)
      return true if model_class.properties.keys.include?(Bulkrax.system_identifier_field)
      raise(
        "#{model_class} does not implement the system_identifier_field: #{Bulkrax.system_identifier_field}"
      )
    end

    def find_collection(collection_identifier)
      Collection.where(
        Bulkrax.system_identifier_field => collection_identifier
      ).detect { |m| m.send(Bulkrax.system_identifier_field).include?(collection_identifier) }
    end
  end
end
