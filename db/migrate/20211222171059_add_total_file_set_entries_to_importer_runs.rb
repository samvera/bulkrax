class AddTotalFileSetEntriesToImporterRuns < ActiveRecord::Migration[5.2]
  def change
    add_column :bulkrax_importer_runs, :total_file_set_entries, :integer, default: 0 unless column_exists?(:bulkrax_importer_runs, :total_file_set_entries)
  end
end
