class AddNextImportAtToBulkraxImporters < ActiveRecord::Migration[5.1]
  def change
    add_column :bulkrax_importers, :next_import_at, :datetime unless column_exists?(:bulkrax_importers, :next_import_at)
  end
end
