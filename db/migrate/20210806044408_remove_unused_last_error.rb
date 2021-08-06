class RemoveUnusedLastError < ActiveRecord::Migration[5.1]
  def change
    remove_column :bulkrax_entries, :last_error
    remove_column :bulkrax_exporters, :last_error
    remove_column :bulkrax_importers, :last_error
  end
end
