class AddParentsToBulkraxImporterRuns < ActiveRecord::Migration[5.2]
  def change
    add_column :bulkrax_importer_runs, :parents, :string, array: true, default: []
  end
end
