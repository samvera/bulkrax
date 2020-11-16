class AddDateFilterAndStatusToBulkraxExporters < ActiveRecord::Migration[5.1]
  def change
    add_column :bulkrax_exporters, :start_date, :date
    add_column :bulkrax_exporters, :finish_date, :date
    add_column :bulkrax_exporters, :work_visibility, :string
  end
end
