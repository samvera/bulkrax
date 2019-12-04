class ChangeTotalRecordsToTotalWorkEntries < ActiveRecord::Migration[5.1]
  def change
    rename_column :bulkrax_importer_runs, :total_records, :total_work_entries
    rename_column :bulkrax_exporter_runs, :total_records, :total_work_entries
  end
end
