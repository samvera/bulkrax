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
    rescue ::CSV::MalformedCSVError => e
      importer.set_status_info(e)
    end

    private

    def import(importer, only_updates_since_last_import)
      importer.only_updates = only_updates_since_last_import || false
      return unless importer.valid_import?

      importer.import_objects
    end

    def unzip_imported_file(parser)
      return unless parser.file? && parser.zip?

      parser.unzip(parser.parser_fields['import_file_path'])
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
