class AddStatusToExporters < ActiveRecord::Migration[5.1]
  def change
    add_column :bulkrax_exporters, :last_error, :text
    add_column :bulkrax_exporters, :last_error_at, :datetime
    add_column :bulkrax_exporters, :last_succeeded_at, :datetime
  end
end
