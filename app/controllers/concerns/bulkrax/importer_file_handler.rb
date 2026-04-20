# frozen_string_literal: true

module Bulkrax
  # rubocop:disable Metrics/ModuleLength
  module ImporterFileHandler
    extend ActiveSupport::Concern

    private

    # Resolves files for validation from either a server-side file path, pre-uploaded Hyrax files, or direct upload params
    # @return [Array<(Array<File>, nil)>] on success, a tuple of [files, nil]
    # @return [Array<(nil, Hash)>] on error, a tuple of [nil, error_response]
    def resolve_validation_files
      if import_via_file_path?
        return [nil, StepperResponseFormatter.error(message: I18n.t('bulkrax.importer.guided_import.validation.file_path_not_exist'))] unless File.exist?(import_file_path)

        [[File.open(import_file_path)], nil]
      elsif params[:uploaded_files].present?
        resolve_hyrax_uploaded_files
      else
        files = params[:importer]&.[](:parser_fields)&.[](:files) || []
        files = [files] unless files.is_a?(Array)
        [files.compact, nil]
      end
    end

    # Loads files from Hyrax::UploadedFile IDs (used by chunked upload flow).
    # Scoped to current_user to prevent accessing another user's uploads.
    def resolve_hyrax_uploaded_files
      uploads = uploaded_files_scope
      return [nil, StepperResponseFormatter.error(message: 'No uploaded files found for the given IDs')] if uploads.empty?

      files = uploads.filter_map do |u|
        path = u.file&.path
        next nil unless path && File.exist?(path)
        File.open(path)
      end
      [files, nil]
    rescue StandardError => e
      Rails.logger.error("Bulkrax: error loading Hyrax uploaded files: #{e.class}: #{e.message}")
      Rails.logger.debug { e.full_message }
      [nil, StepperResponseFormatter.error(message: 'Failed to load uploaded files')]
    end

    def uploaded_files_scope
      return [] unless defined?(::Hyrax)

      base = Hyrax::UploadedFile.where(id: params[:uploaded_files])
      if respond_to?(:current_user) && current_user.present?
        base.where(user_id: current_user.id)
      else
        base.none
      end
    end

    def resolve_create_files
      if params[:uploaded_files].present?
        uploads = uploaded_files_scope
        uploads.filter_map do |u|
          path = u.file&.path
          next nil unless path && File.exist?(path)
          File.open(path)
        end
      else
        extract_uploaded_files
      end
    end

    def extract_uploaded_files
      files_param = params[:importer]&.[](:parser_fields)&.[](:files)
      return [] if files_param.blank?

      files_param.is_a?(Array) ? files_param.compact : [files_param].compact
    end

    # Scans the given files for a CSV and a ZIP by file extension
    # @param files [Array<File, ActionDispatch::Http::UploadedFile>] the resolved files to search
    # @return [Array<(File, nil), (nil, File), (File, File), (nil, nil)>] a tuple of [csv_file, zip_file]; either may be nil
    def select_csv_and_zip(files)
      csv_file = files.find { |f| filename_for(f)&.end_with?('.csv') }
      zip_file = files.find { |f| filename_for(f)&.end_with?('.zip') }
      [csv_file, zip_file]
    end

    # Returns a filename from any file-like object (ActionDispatch upload, File, or Tempfile)
    def filename_for(file)
      if file.respond_to?(:original_filename)
        file.original_filename
      elsif file.respond_to?(:path)
        file.path
      end
    end

    # Opens a ZIP and extracts the CSV content into a StringIO while the archive is open
    # @param zip_file [File] the ZIP file to search
    # @return [Array<(StringIO, nil)>] on success, a tuple of [csv_file, nil]
    # @return [Array<(nil, Hash)>] on error, a tuple of [nil, error_response]
    def extract_csv_from_zip(zip_file)
      csv_file = nil
      error = nil
      Zip::File.open(zip_file.path) do |zip|
        result = locate_csv_entry_in_zip(zip)
        if result.is_a?(Hash) && result[:messages]
          error = result
        elsif result
          csv_file = StringIO.new(result.get_input_stream.read)
        end
      end
      [csv_file, error]
    end

    # Finds a CSV entry in a ZIP by traversing directory levels, preferring the shallowest
    # @param zip [Zip::File] the open ZIP archive to search
    # @return [Zip::Entry] the CSV entry on success
    # @return [Hash] an error response hash if no CSV is found or multiple CSVs are ambiguous
    def locate_csv_entry_in_zip(zip)
      csv_entries = group_entries_by_directory_level(zip)

      return StepperResponseFormatter.error(message: I18n.t('bulkrax.importer.guided_import.validation.no_csv_in_zip')) if csv_entries.empty?

      csv_by_depth = get_directory_depth_for_each_csv(csv_entries)
      csvs_at_level = determine_csvs_at_shallowest_level(csv_by_depth)

      return StepperResponseFormatter.error(message: I18n.t('bulkrax.importer.guided_import.validation.multiple_csv')) if csvs_at_level.size > 1

      csvs_at_level.first
    end

    def group_entries_by_directory_level(zip)
      zip.select { |entry| entry.name.end_with?('.csv') && !entry.directory? }
    end

    def get_directory_depth_for_each_csv(entries)
      entries.group_by { |entry| entry.name.count('/') }
    end

    def determine_csvs_at_shallowest_level(csv_by_depth)
      shallowest_depth = csv_by_depth.keys.min
      csv_by_depth[shallowest_depth]
    end

    # Persists uploaded file(s) and/or cloud files onto the importer record.
    # @param file [ActionDispatch::Http::UploadedFile, nil] a directly uploaded file
    # @param cloud_files [Hash, nil] cloud file paths from browse-everything
    # @param uploads [ActiveRecord::Relation, Array, nil] Hyrax::UploadedFile records
    def files_for_import(file, cloud_files, uploads)
      return if file.blank? && cloud_files.blank? && uploads.blank?

      @importer[:parser_fields]['import_file_path'] = @importer.parser.write_import_file(file) if file.present?
      if cloud_files.present?
        @importer[:parser_fields]['cloud_file_paths'] = cloud_files
        # For BagIt, there will only be one bag, so we get the file_path back and set import_file_path
        # For CSV, we expect only file uploads, so we won't get the file_path back
        # and we expect the import_file_path to be set already
        target = @importer.parser.retrieve_cloud_files(cloud_files, @importer)
        @importer[:parser_fields]['import_file_path'] = target if target.present?
      end

      if uploads.present?
        uploads.each do |upload|
          @importer[:parser_fields]['import_file_path'] = @importer.parser.write_import_file(upload.file.file)
        end
      end

      @importer.save
    end

    def write_files(files)
      csv_file, zip_file = select_csv_and_zip(files)

      csv_path = write_file_if_present(csv_file)
      zip_path = write_file_if_present(zip_file)

      return unless csv_path || zip_path

      # Determine import_file_path: prefer CSV, fallback to ZIP
      @importer.parser_fields['import_file_path'] = csv_path || zip_path
      @importer.parser_fields['attachments_zip_path'] = zip_path if zip_path && csv_path

      @importer.save
    rescue StandardError => e
      Rails.logger.error("Bulkrax::ImporterFileHandler#write_files failed: #{e.message}")
      raise
    end

    def write_file_if_present(file)
      return nil unless file

      if file.respond_to?(:original_filename)
        @importer.parser.write_import_file(file)
      else
        dest_path = File.join(@importer.parser.path_for_import, File.basename(file.path))
        FileUtils.cp(file.path, dest_path)
        dest_path
      end
    end

    def close_file_handles(files)
      return unless files.is_a?(Array)
      files.each { |f| f.close if f.respond_to?(:close) }
    end

    def import_via_file_path?
      import_file_path.present?
    end

    def import_file_path
      @file_path ||= params[:importer]&.[](:parser_fields)&.[](:import_file_path)
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
