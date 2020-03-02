# frozen_string_literal: true
module Bulkrax
  class XmlParser < ApplicationParser
    def entry_class
      Bulkrax::XmlEntry
    end

    # @todo not yet supported
    def collection_entry_class; end
    def create_collections; end
    def import_fields; end

    def valid_import?
      raise 'No metadata files found' if metadata_paths.blank?
      raise 'No records found' if records.blank?
      true
    rescue StandardError => e
      # status_info(e)
      errors.add(:base, e.class.to_s.to_sym, message: e.message)
      false
    end
    
    # For multiple, we expect to find metadata for multiple works in the given metadata file(s)
    # For single, we expect to find metadata for a single work in the given metadata file(s)
    #  if the file contains more than one record, we take only the first
    # In either case there may be multiple metadata files returned by metadata_paths
    def records(opts = {})
      @records ||=
      if parser_fields['import_type'] == 'multiple'
        r = []
        metadata_paths.map { | md |
          # Retrieve all records
          elements = entry_class.read_data(md).xpath("//#{record_element}")
          r += elements.map { |el| entry_class.data_for_entry(el, md) }
        }
        # Flatten because we may have multiple records per array
        r.compact.flatten
      elsif parser_fields['import_type'] == 'single'
        metadata_paths.map { | md | 
          entry_class.data_for_entry(
            # Take only the first record
            entry_class.read_data(md).xpath("//#{record_element}").first,
            md
          # No need to flatten because we take only the first record
          ) }.compact
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
          Dir.glob("#{File.dirname(real_import_file_path)}/**/*").reject { |f| File.file?(f) == false }
        # In the supplied directory
        else
          Dir.glob("#{real_import_file_path}/**/*").reject { |f| File.file?(f) == false }
        end
    end

    # If the import_file_path is an xml file, return that
    # Otherwise return all xml files in the given folder
    def metadata_paths
      @metadata_paths ||= 
      if file? && MIME::Types.type_for(real_import_file_path).include?('application/xml')
        [real_import_file_path]
      else
        file_paths.select { |f| MIME::Types.type_for(f).include?('application/xml') }
      end
    end

    def create_works
      records.each_with_index do |record, index|
        next if record[:source_identifier].blank?
        break if !limit.nil? && index >= limit

        seen[record[:source_identifier]] = true
        new_entry = find_or_create_entry(entry_class, record[:source_identifier], 'Bulkrax::Importer', record)
        ImportWorkJob.send(perform_method, new_entry.id, current_importer_run.id)
        increment_counters(index)
      end
    rescue StandardError => e
      # status_info(e)
      errors.add(:base, e.class.to_s.to_sym, message: e.message)
    end

    def total
      records.size
    end
  end
end
