class AddLastImportedAtToBulkraxImporters < ActiveRecord::Migration[5.1]
  def change
    add_column :bulkrax_importers, :last_imported_at, :datetime unless column_exists?(:bulkrax_importers, :last_imported_at)
  end
end
