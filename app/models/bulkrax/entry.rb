# frozen_string_literal: true

module Bulkrax
  # Custom error class for collections_created?
  class CollectionsCreatedError < RuntimeError; end
  class OAIError < RuntimeError; end
  class Entry < ApplicationRecord
    include Bulkrax::HasMatchers
    include Bulkrax::HasLocalProcessing
    include Bulkrax::ImportBehavior
    include Bulkrax::ExportBehavior

    belongs_to :importerexporter, polymorphic: true
    serialize :parsed_metadata, JSON
    # Do not serialize raw_metadata as so we can support xml or other formats
    serialize :collection_ids, Array
    serialize :last_error, JSON

    attr_accessor :all_attrs, :last_exception

    delegate :parser, :mapping, :replace_files, to: :importerexporter

    delegate :client,
             :collection_name,
             :user,
             to: :parser

    # Retrieve fields from the file
    # @param data - the source data
    # @return Array
    def self.fields_from_data(_data)
      raise 'Not Implemented'
    end

    # Read the data from the supplied path
    # @param path - path to the data file
    # @return the data from the file
    def self.read_data(_path)
      raise 'Not Implemented'
    end

    # Returns formatted data from the given file for a single Entry
    # @param data - the data from the metadata file
    # @param path - the path to the metadata file - used by RDF to get the file_paths
    # @return Hash containing the data (the entry build_metadata method will know what to expect in the hash)
    def self.data_for_entry(_data, _path = nil)
      raise 'Not Implemented'
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

    def status
      if self.last_error_at.present?
        'failed'
      elsif self.last_succeeded_at.present?
        'succeeded'
      else
        'waiting'
      end
    end

    def status_at
      case status
      when 'succeeded'
        self.last_succeeded_at
      when 'failed'
        self.last_error_at
      end
    end

    def status_info(e = nil)
      if e.nil?
        self.last_error = nil
        self.last_error_at = nil
        self.last_exception = nil
        self.last_succeeded_at = Time.current
      else
        self.last_error =  { error_class: e.class.to_s, error_message: e.message, error_trace: e.backtrace }
        self.last_error_at = Time.current
        self.last_exception = e
      end
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
