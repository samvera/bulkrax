class RenameChildrenCountersToRelationships < ActiveRecord::Migration[5.2]
  def change
    rename_column :bulkrax_importer_runs, :processed_children, :processed_relationships
    rename_column :bulkrax_importer_runs, :failed_children, :failed_relationships
  end
end
