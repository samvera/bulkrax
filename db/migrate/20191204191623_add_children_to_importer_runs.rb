class AddChildrenToImporterRuns < ActiveRecord::Migration[5.1]
  def change
    add_column :bulkrax_importer_runs, :processed_children, :integer, default: 0
    add_column :bulkrax_importer_runs, :failed_children, :integer, default: 0
  end
end
