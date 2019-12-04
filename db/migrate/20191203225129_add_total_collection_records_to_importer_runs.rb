class AddTotalCollectionRecordsToImporterRuns < ActiveRecord::Migration[5.1]
  def change
    add_column :bulkrax_importer_runs, :total_collection_entries, :integer, default: 0
  end
end
