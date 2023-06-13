class AddRelationshipImportOnlyToImporters < ActiveRecord::Migration[5.2]
  def change
    add_column :bulkrax_importers, :import_relationships_only, :boolean, default: false unless column_exists?(:bulkrax_importers, :import_relationships_only)
  end
end
