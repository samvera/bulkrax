class AddParentsToBulkraxImporterRuns < ActiveRecord::Migration[5.1]
  def change
    add_column :bulkrax_importer_runs, :parents, :text, array: true, default: []
  end
end
