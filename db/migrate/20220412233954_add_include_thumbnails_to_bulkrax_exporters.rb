class AddIncludeThumbnailsToBulkraxExporters < ActiveRecord::Migration[5.2]
  def change
    add_column :bulkrax_exporters, :include_thumbnails, :boolean, default: false unless column_exists?(:bulkrax_exporters, :include_thumbnails)
  end
end
