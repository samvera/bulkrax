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

    def records(opts = {})
      @records ||=
      if parser_fields['import_type'] == 'multiple'
        r = []
        metadata_paths.map { | md | 
          elements = entry_class.read_data(md).xpath("//#{record_element}")
          r += elements.map { |el| entry_class.data_for_entry(el, md) }
        }
        r.compact.flatten
      elsif parser_fields['import_type'] == 'single'
        metadata_paths.map { | md | 
          entry_class.data_for_entry(
            entry_class.read_data(md).xpath("//#{record_element}").first,
            md
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

    # Return all xml files
    def metadata_paths
      @metadata_paths ||= file_paths.select { |f| MIME::Types.type_for(f).include?('application/xml')}
    end

    def create_works
      records.each_with_index do |record, index|
        next if record[:source_identifier].blank?
        break if !limit.nil? && index >= limit

        seen[record[:source_identifier]] = true
        new_entry = find_or_create_entry(entry_class, record[:source_identifier], 'Bulkrax::Importer', record)
        ImportWorkJob.perform_later(new_entry.id, current_importer_run.id)
        increment_counters(index)
      end
    rescue StandardError => e
      errors.add(:base, e.class.to_s.to_sym, message: e.message)
    end

    # def valid_import?; end (default: true)
    def total
      records.size
    end
  end
end
