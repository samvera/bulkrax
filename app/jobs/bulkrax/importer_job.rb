# frozen_string_literal: true

module Bulkrax
  class ImporterJob < ApplicationJob
    queue_as :import

    def perform(importer_id, only_updates_since_last_import = false)
      importer = Importer.find(importer_id)

      importer.current_run
      unzip_imported_file(importer.parser)
      import(importer, only_updates_since_last_import)
      update_current_run_counters(importer)
      schedule(importer) if importer.schedulable?
    end

    def import(importer, only_updates_since_last_import)
      importer.only_updates = only_updates_since_last_import || false
      return unless importer.valid_import?

      importer.import_collections
      importer.import_works
    end

    def unzip_imported_file(parser)
      return unless parser.file? && parser.zip?

      parser.unzip(parser.parser_fields['import_file_path'])
    end

    def update_current_run_counters(importer)
      importer.current_run.total_work_entries = importer.limit || importer.parser.works_total
      importer.current_run.total_collection_entries = importer.parser.collections_total
      importer.current_run.save!
    end

    def schedule(importer)
      ImporterJob.set(wait_until: importer.next_import_at).perform_later(importer.id, true)
    end
  end
end
