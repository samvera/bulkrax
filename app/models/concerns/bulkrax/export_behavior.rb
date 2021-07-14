# frozen_string_literal: true
module Bulkrax
  module ExportBehavior
    extend ActiveSupport::Concern

    delegate :export_type, :exporter_export_path, to: :importerexporter

    def build_for_exporter
      build_export_metadata
      write_files if export_type == 'full' && !importerexporter.parser_klass.include?('Bagit')
    rescue RSolr::Error::Http, CollectionsCreatedError => e
      raise e
    rescue StandardError => e
      status_info(e)
    else
      status_info
    end

    def build_export_metadata
      raise StandardError, 'not implemented'
    end

    def hyrax_record
      @hyrax_record ||= ActiveFedora::Base.find(self.identifier)
    end

    def write_files
      return if hyrax_record.is_a?(Collection)
      hyrax_record.file_sets.each do |fs|
        path = File.join(exporter_export_path, 'files')
        FileUtils.mkdir_p(path)
        file = filename(fs)
        require 'open-uri'
        io = open(fs.original_file.uri)
        next if file.blank?
        File.open(File.join(path, file), 'wb') do |f|
          f.write(io.read)
          f.close
        end
      end
    end

    # Append the file_set id to ensure a unique filename
    def filename(file_set)
      return if file_set.original_file.blank?
      fn = file_set.original_file.file_name.first
      mime = Mime::Type.lookup(file_set.original_file.mime_type)
      ext_mime = MIME::Types.of(file_set.original_file.file_name).first
      if fn.include?(file_set.id)
        return fn if mime.to_s == ext_mime.to_s
        return "#{fn}.#{mime.to_sym}"
      else
        return "#{file_set.id}_#{fn}" if mime.to_s == ext_mime.to_s
        return "#{file_set.id}_#{fn}.#{mime.to_sym}"
      end
    end
  end
end
