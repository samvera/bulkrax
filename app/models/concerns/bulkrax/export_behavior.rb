# frozen_string_literal: true

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
      # return if there are no files on the fileset
      return if Bulkrax.object_factory.original_file(fileset: file_set).blank?

      fn = Bulkrax.object_factory.filename_for(fileset: file_set)
      file = Bulkrax.object_factory.original_file(fileset: file_set)
      ext = file_extension(file: file, filename: fn)

      # Prepend the file_set id to ensure a unique filename
      filename = File.basename(fn, ".*")
      # Skip modification if file already has ID or we're in metadata-only mode
      if fn.include?(file_set.id) || importerexporter.metadata_only?
        # keep filename as is
      else
        filename = "#{file_set.id}_#{filename}"
      end
      filename = ext.present? ? "#{filename}.#{ext}" : fn

      # Remove extension, truncate and reattach
      "#{File.basename(filename, ext)[0...(220 - ext.length)]}#{ext}"
    end

    ##
    # Generate the appropriate file extension based on the mime type of the file
    # @return [String] the file extension for the given file
    def file_extension(file:, filename:)
      declared_mime = ::Marcel::MimeType.for(declared_type: file.mime_type)
      # validate the declared mime type
      declared_mime = ::Marcel::MimeType.for(name: filename) if declared_mime.nil? || declared_mime == "application/octet-stream"
      # convert the mime type to a file extension
      Mime::Type.lookup(declared_mime).symbol.to_s
    rescue Mime::Type::InvalidMimeType
      nil
    end
  end
end
