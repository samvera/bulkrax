module Bulkrax
  class ImporterJob < ApplicationJob
    queue_as :import

    def perform(importer_id, only_updates_since_last_import = false)
      importer = Importer.find(importer_id)

      import(importer, only_updates_since_last_import)
      schedule(importer) if importer.schedulable?
    end

    def import(importer, only_updates_since_last_import)
      importer.validate_import
      importer.import_collections
      importer.import_works(only_updates_since_last_import)
      importer.add_parent_child_relationships
    end

    def schedule(importer)
      ImporterJob.set(wait_until: importer.next_import_at).perform_later(importer.id, true)
    end
  end
end
