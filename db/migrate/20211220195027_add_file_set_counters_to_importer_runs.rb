class AddFileSetCountersToImporterRuns < ActiveRecord::Migration[5.2]
  def change
    add_column :bulkrax_importer_runs, :processed_file_sets, :integer, default: 0
    add_column :bulkrax_importer_runs, :failed_file_sets, :integer, default: 0
  end
end
