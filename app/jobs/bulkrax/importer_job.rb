# frozen_string_literal: true

module Bulkrax
  class ImporterJob < ApplicationJob
    queue_as Bulkrax.config.ingest_queue_name

    def perform(importer_id, only_updates_since_last_import = false)
      importer = Importer.find(importer_id)
      return schedule(importer, Time.zone.now + 3.minutes, 'Rescheduling: cloud files are not ready yet') unless all_files_completed?(importer)

      importer.current_run
      unzip_imported_file(importer.parser)
      import(importer, only_updates_since_last_import)
      update_current_run_counters(importer)
      schedule(importer) if importer.schedulable?
    rescue ::CSV::MalformedCSVError, Bulkrax::UnzipError => e
      importer.set_status_info(e)
    end

    private

    def import(importer, only_updates_since_last_import)
      importer.only_updates = only_updates_since_last_import || false
      return unless importer.valid_import?

      importer.import_objects
    end

    # Populates `importer_unzip_path` with the uploaded file(s), leaving
    # the working directory in the shape each parser expects.
    #
    # Dispatch by parser capability rather than class name:
    # - CsvParser (and subclasses that replicate its shape) implements
    #   `#unzip_with_primary_csv` and `#unzip_attachments_only`, which
    #   place the primary CSV at root and attachments under `files/`.
    # - Other parsers (XML, raw BagIt) inherit the base-class `#unzip`,
    #   which extracts the zip verbatim.
    # - The separate attachments-zip flow is CSV-only (guided import is
    #   the only UI that produces it).
    #
    # A retry of this job gets a clean working directory: any prior
    # extraction state from an earlier attempt is wiped, so nothing runs
    # against partially-populated state.
    def unzip_imported_file(parser)
      return unless parser.file?

      reset_unzip_path(parser)

      import_file_path = parser.parser_fields['import_file_path']
      attachments_zip_path = parser.parser_fields['attachments_zip_path']

      if parser.zip?
        if parser.respond_to?(:unzip_with_primary_csv)
          parser.unzip_with_primary_csv(import_file_path)
        else
          parser.unzip(import_file_path)
        end
      elsif parser.respond_to?(:unzip_attachments_only) && parser.zip_file?(attachments_zip_path)
        parser.copy_file(import_file_path)
        parser.unzip_attachments_only(attachments_zip_path)
      else
        parser.copy_file(import_file_path)
      end

      parser.remove_spaces_from_filenames if parser.respond_to?(:remove_spaces_from_filenames)
    end

    def reset_unzip_path(parser)
      path = parser.importer_unzip_path
      FileUtils.rm_rf(path) if Dir.exist?(path)
      FileUtils.mkdir_p(path)
    end

    def update_current_run_counters(importer)
      importer.current_run.total_work_entries = importer.limit || importer.parser.works_total
      importer.current_run.total_collection_entries = importer.parser.collections_total
      importer.current_run.total_file_set_entries = importer.parser.file_sets_total
      importer.current_run.save!
    end

    def schedule(importer, wait_until = importer.next_import_at, message = nil)
      Rails.logger.info message if message
      ImporterJob.set(wait_until: wait_until).perform_later(importer.id, true)
    end

    # checks the file sizes of the download files to match the original files
    def all_files_completed?(importer)
      cloud_files = importer.parser_fields['cloud_file_paths']
      original_files = importer.parser_fields['original_file_paths']
      return true unless cloud_files.present? && original_files.present?

      imported_file_sizes = cloud_files.map { |_, v| v['file_size'].to_i }
      original_file_sizes = original_files.map { |imported_file| File.size(imported_file) }

      original_file_sizes == imported_file_sizes
    end
  end
end
