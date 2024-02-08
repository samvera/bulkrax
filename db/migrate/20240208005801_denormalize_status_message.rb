class DenormalizeStatusMessage < ActiveRecord::Migration[5.2]
  def change
    add_column :bulkrax_entries, :status_message, :string, default: 'Pending'
    add_column :bulkrax_importers, :status_message, :string, default: 'Pending'
    add_column :bulkrax_exporters, :status_message, :string, default: 'Pending'
  end
end
