class AddGeneratedMetadataToBulkraxExporters < ActiveRecord::Migration[5.2]
  def change
    add_column :bulkrax_exporters, :generated_metadata, :boolean, default: false unless column_exists?(:bulkrax_exporters, :generated_metadata)
  end
end
