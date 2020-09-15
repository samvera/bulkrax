class AddValidateOnlyToBulkraxImporters < ActiveRecord::Migration[5.1]
  def change
    add_column :bulkrax_importers, :validate_only, :boolean unless column_exists?(:bulkrax_importers, :validate_only)
  end
end
