class RenameBulkraxImporterRunToImporterRun < ActiveRecord::Migration[5.2]
  def change
    if column_exists?(:bulkrax_pending_relationships, :bulkrax_importer_run_id)
      rename_column :bulkrax_pending_relationships, :bulkrax_importer_run_id, :importer_run_id
    end
  end
end
