# frozen_string_literal: true

module Bulkrax
  class XmlParser < ApplicationParser
    def entry_class
      Bulkrax::XmlEntry
    end

    # @todo not yet supported
    def collection_entry_class; end

    # @todo not yet supported
    def create_collections; end

    # @todo not yet supported
    def import_fields; end

    def valid_import?
      raise StandardError, 'No metadata files found' if metadata_paths.blank?
      raise StandardError, 'No records found' if records.blank?
      true
    rescue StandardError => e
      status_info(e)
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
            r += elements.map { |el| entry_class.data_for_entry(el) }
          end
          # Flatten because we may have multiple records per array
          r.compact.flatten
        elsif parser_fields['import_type'] == 'single'
          metadata_paths.map do |md|
            data = entry_class.read_data(md).xpath("//#{record_element}").first # Take only the first record
            entry_class.data_for_entry(data)
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
        if file? && MIME::Types.type_for(import_file_path).include?('application/xml')
          [import_file_path]
        else
          file_paths.select do |f|
            MIME::Types.type_for(f).include?('application/xml') &&
              f.include?("import_#{importerexporter.id}")
          end
        end
    end

    def create_works
      records.each_with_index do |record, index|
        next if record[source_identifier].blank?
        break if !limit.nil? && index >= limit

        seen[record[source_identifier]] = true
        new_entry = find_or_create_entry(entry_class, record[source_identifier], 'Bulkrax::Importer', record)
        if record[:delete].present?
          DeleteWorkJob.send(perform_method, new_entry, current_run)
        else
          ImportWorkJob.send(perform_method, new_entry.id, current_run.id)
        end
        increment_counters(index)
      end
    rescue StandardError => e
      status_info(e)
    end

    def total
      records.size
    end
  end
end
