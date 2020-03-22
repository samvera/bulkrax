class RemoveForeignKeyFromBulkraxEntries < ActiveRecord::Migration[5.1]
  def change
    remove_foreign_key :bulkrax_entries, :bulkrax_importers
  end
end
