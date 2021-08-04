# frozen_string_literal: true

module Bulkrax
  # Custom error class for collections_created?
  class CollectionsCreatedError < RuntimeError; end
  class OAIError < RuntimeError; end
  class Entry < ApplicationRecord
    include Bulkrax::HasMatchers
    include Bulkrax::ImportBehavior
    include Bulkrax::ExportBehavior
    include Bulkrax::StatusInfo
    include Bulkrax::HasLocalProcessing

    belongs_to :importerexporter, polymorphic: true
    alias importer importerexporter
    alias exporter importerexporter
    has_many :statuses, as: :statusable, dependent: :destroy

    serialize :parsed_metadata, JSON
    # Do not serialize raw_metadata as so we can support xml or other formats
    serialize :collection_ids, Array
    serialize :last_error, JSON

    paginates_per 5

    attr_accessor :all_attrs

    delegate :parser, :mapping, :replace_files, :update_files, to: :importerexporter

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

    def source_identifier
      parser&.source_identifier.to_s || 'source_identifier'
    end

    def work_identifier
      parser&.work_identifier.to_s || 'source'
    end

    def self.collection_field
      Bulkrax.collection_field_mapping[self.to_s]
    end

    def self.children_field
      Bulkrax.parent_child_field_mapping[self.to_s]
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

    def valid_system_id(model_class)
      return true if model_class.properties.keys.include?(work_identifier)
      raise(
        "#{model_class} does not implement the system_identifier_field: #{work_identifier}"
      )
    end

    def last_run
      self.importerexporter&.last_run
    end

    def find_collection(collection_identifier)
      Collection.where(
        work_identifier => collection_identifier
        ).detect { |m| m.send(work_identifier).include?(collection_identifier) }
    end
  end
end
