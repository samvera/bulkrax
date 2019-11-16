require 'fileutils'

module Bulkrax
  module ExportBehavior
    extend ActiveSupport::Concern

    delegate :export_type, :exporter_export_path, to: :importerexporter

    def build_for_exporter
      build_export_metadata
      write_files if export_type == 'full'
    end

    def build_export_metadata
      raise 'not implemented'
    end

    def work
      @work ||= ActiveFedora::Base.find(self.identifier)
    end

    # @todo is there a better way to do this?
    def write_files
      return if work.is_a?(Collection)
      work.file_sets.each do |fs|
        path = File.join(exporter_export_path, 'files', work.id)
        FileUtils.mkdir_p(path)
        require 'open-uri'
        io = open(fs.original_file.uri)
        file = filename(fs)
        next if file.blank?
        File.open(File.join(path, file), 'wb') do |f|
          f.write(io.read)
          f.close
        end
      end
    end

    def filename(file_set)
      return if file_set.original_file.blank?
      "#{file_set.id}_#{file_set.original_file.file_name.first}.#{Mime::Type.lookup(file_set.original_file.mime_type).to_sym}"
    end
  end
end
