module Bulkrax
  class ImporterJob < ApplicationJob
    queue_as :import

    def perform(importer_id, only_updates_since_last_import=false)
      start = Time.current
      importer = Importer.find(id)

      importer.import_works
      importer.last_imported_at = start
      if importer.schedulable?
        ImporterJob.set(wait_until: importer.next_import_at).perform_later(importer.id, true)
      end

    end
  end
end
