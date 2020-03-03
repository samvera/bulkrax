class AddValidateOnlyToBulkraxImporters < ActiveRecord::Migration[5.1]
  def change
    add_column :bulkrax_importers, :validate_only, :boolean
  end
end
