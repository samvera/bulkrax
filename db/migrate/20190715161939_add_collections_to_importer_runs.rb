class AddCollectionsToImporterRuns < ActiveRecord::Migration[5.1]
  def change
    add_column :bulkrax_importer_runs, :processed_collections, :integer, default: 0
    add_column :bulkrax_importer_runs, :failed_collections, :integer, default: 0
  end
end
