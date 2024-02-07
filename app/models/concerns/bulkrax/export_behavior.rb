# frozen_string_literal: true
require 'marcel'

module Bulkrax
  module ExportBehavior
    extend ActiveSupport::Concern

    delegate :export_type, :exporter_export_path, to: :importerexporter

    def build_for_exporter
      build_export_metadata
    rescue RSolr::Error::Http, CollectionsCreatedError => e
      raise e
    rescue StandardError => e
      set_status_info(e)
    else
      set_status_info
    end

    def build_export_metadata
      raise StandardError, 'not implemented'
    end

    def hyrax_record
      @hyrax_record ||= Bulkrax.object_factory.find(self.identifier)
    end

    # Prepend the file_set id to ensure a unique filename and also one that is not longer than 255 characters
    def filename(file_set)
      return if file_set.original_file.blank?
      fn = file_set.original_file.file_name.first
      mime = ::Marcel::MimeType.for(file_set.original_file.mime_type)
      ext_mime = ::Marcel::MimeType.for(file_set.original_file.file_name)
      if fn.include?(file_set.id) || importerexporter.metadata_only?
        filename = "#{fn}.#{mime.to_sym}"
        filename = fn if mime.to_s == ext_mime.to_s
      else
        filename = "#{file_set.id}_#{fn}.#{mime.to_sym}"
        filename = "#{file_set.id}_#{fn}" if mime.to_s == ext_mime.to_s
      end
      # Remove extention truncate and reattach
      ext = File.extname(filename)
      "#{File.basename(filename, ext)[0...(220 - ext.length)]}#{ext}"
    end
  end
end
