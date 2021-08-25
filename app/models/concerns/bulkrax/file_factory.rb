# frozen_string_literal: true

module Bulkrax
  module FileFactory
    extend ActiveSupport::Concern

    # Find existing files or upload new files. This assumes a Work will have unique file titles;
    #   and that those file titles will not have changed
    # could filter by URIs instead (slower).
    # When an uploaded_file already exists we do not want to pass its id in `file_attributes`
    # otherwise it gets reuploaded by `work_actor`.
    # support multiple files; ensure attributes[:file] is an Array
    def upload_ids
      return [] if klass == Collection
      attributes[:file] = file_paths
      import_files
    end

    def file_attributes(update_files = false)
      @update_files = update_files
      hash = {}
      return hash if klass == Collection
      hash[:uploaded_files] = upload_ids if attributes[:file].present?
      hash[:remote_files] = new_remote_files if new_remote_files.present?
      hash
    end

    # Its possible to get just an array of strings here, so we need to make sure they are all hashes
    def parsed_remote_files
      return @parsed_remote_files if @parsed_remote_files.present?
      @parsed_remote_files = attributes[:remote_files] || []
      @parsed_remote_files = @parsed_remote_files.map do |file_value|
        if file_value.is_a?(Hash)
          file_value
        elsif file_value.is_a?(String)
          name = Bulkrax::Importer.safe_uri_filename(file_value)
          { url: file_value, file_name: name }
        else
          Rails.logger.error("skipped remote file #{file_value} because we do not recognize the type")
          nil
        end
      end
      @parsed_remote_files.delete(nil)
      @parsed_remote_files
    end

    def new_remote_files
      @new_remote_files ||= if object.present? && object.file_sets.present?
                              parsed_remote_files.select do |file|
                                # is the url valid?
                                is_valid = file[:url]&.match(URI::ABS_URI)
                                # does the file already exist
                                is_existing = object.file_sets.detect { |f| f.import_url && f.import_url == file[:url] }
                                is_valid && !is_existing
                              end
                            else
                              parsed_remote_files.select do |file|
                                file[:url]&.match(URI::ABS_URI)
                              end
                            end
    end

    def file_paths
      @file_paths ||= Array.wrap(attributes[:file])&.select { |file| File.exist?(file) }
    end

    # Retrieve the orginal filenames for the files to be imported
    def work_files_filenames
      object.file_sets.map { |fn| fn.original_file.file_name.to_a }.flatten if object.present? && object.file_sets.present?
    end

    # Retrieve the filenames for the files to be imported
    def import_files_filenames
      file_paths.map { |f| f.split('/').last }
    end

    # Called if #replace_files is true
    # Destroy all file_sets for this object
    # Reload the object to ensure the remaining methods have the most up to date object
    def destroy_existing_files
      return unless object.present? && object.file_sets.present?
      object.file_sets.each do |fs|
        Hyrax::Actors::FileSetActor.new(fs, @user).destroy
      end
      @object = object.reload
      log_deleted_fs(object)
    end

    def set_removed_filesets
      local_file_sets.each do |fileset|
        fileset.files.first.create_version
        opts = {}
        opts[:path] = fileset.files.first.id.split('/', 2).last
        opts[:original_name] = 'removed.png'
        opts[:mime_type] = 'image/png'

        fileset.add_file(File.open(Bulkrax.removed_image_path), opts)
        fileset.save
        ::CreateDerivativesJob.set(wait: 1.minute).perform_later(fileset, fileset.files.first.id)
      end
    end

    def local_file_sets
      @local_file_sets ||= object&.ordered_file_sets
    end

    def import_files
      paths = file_paths.map { |path| import_file(path) }.compact
      set_removed_filesets if local_file_sets.present?
      paths
    end

    def import_file(path)
      u = Hyrax::UploadedFile.new
      u.user_id = @user.id
      u.file = CarrierWave::SanitizedFile.new(path)
      update_filesets(u)
    end

    def update_filesets(current_file)
      if @update_files && local_file_sets.present?
        fileset = local_file_sets.shift
        return nil if fileset.files.first.checksum.value == Digest::SHA1.file(current_file.file.path).to_s

        fileset.files.first.create_version
        opts = {}
        opts[:path] = fileset.files.first.id.split('/', 2).last
        opts[:original_name] = current_file.file.file.original_filename
        opts[:mime_type] = current_file.file.content_type

        fileset.add_file(File.open(current_file.file.to_s), opts)
        fileset.save
        ::CreateDerivativesJob.set(wait: 1.minute).perform_later(fileset, fileset.files.first.id)
        nil
      else
        current_file.save
        current_file.id
      end
    end
  end
end
