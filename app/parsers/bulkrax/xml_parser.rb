# frozen_string_literal: true
require 'marcel'

module Bulkrax
  class XmlParser < ApplicationParser
    def entry_class
      Bulkrax::XmlEntry
    end

    # @todo not yet supported
    def collection_entry_class; end

    # @todo not yet supported
    def create_collections
      raise NotImplementedError
    end

    # @todo not yet supported
    def file_set_entry_class; end

    # @todo not yet supported
    def create_file_sets
      raise NotImplementedError
    end

    def file_sets
      raise NotImplementedError
    end

    def collections
      raise NotImplementedError
    end

    def works
      records
    end

    # TODO: change to differentiate between collection and work records when adding ability to import collection metadata
    def works_total
      total
    end

    # @todo not yet supported
    def import_fields; end

    def valid_import?
      raise StandardError, 'No metadata files found' if metadata_paths.blank?
      raise StandardError, 'No records found' if records.blank?
      true
    rescue StandardError => e
      set_status_info(e)
      false
    end

    # For multiple, we expect to find metadata for multiple works in the given metadata file(s)
    # For single, we expect to find metadata for a single work in the given metadata file(s)
    #  if the file contains more than one record, we take only the first
    # In either case there may be multiple metadata files returned by metadata_paths
    def records(_opts = {})
      @records ||=
        if parser_fields['import_type'] == 'multiple'
          r = []
          metadata_paths.map do |md|
            # Retrieve all records
            elements = entry_class.read_data(md).xpath("//#{record_element}")
            r += elements.map { |el| entry_class.data_for_entry(el, source_identifier, self) }
          end
          # Flatten because we may have multiple records per array
          r.compact.flatten
        elsif parser_fields['import_type'] == 'single'
          metadata_paths.map do |md|
            data = entry_class.read_data(md).xpath("//#{record_element}").first # Take only the first record
            entry_class.data_for_entry(data, source_identifier, self)
          end.compact # No need to flatten because we take only the first record
        end
    end

    def record_element
      parser_fields['record_element']
    end

    # Return all files in the import directory and sub-directories
    def file_paths
      @file_paths ||=
        # Relative to the file
        if file?
          Dir.glob("#{File.dirname(import_file_path)}/**/*").reject { |f| File.file?(f) == false }
        # In the supplied directory
        else
          Dir.glob("#{import_file_path}/**/*").reject { |f| File.file?(f) == false }
        end
    end

    # If the import_file_path is an xml file, return that
    # Otherwise return all xml files in the given folder
    def metadata_paths
      @metadata_paths ||=
        if file? && good_file_type?(import_file_path)
          [import_file_path]
        else
          file_paths.select do |f|
            good_file_type?(f) && f.include?("import_#{importerexporter.id}")
          end
        end
    end

    def good_file_type?(path)
      %w[.xml .xls .xsd].include?(File.extname(path)) || ::Marcel::MimeType.for(path).include?('application/xml')
    end

    def total
      records.size
    end
  end
end
