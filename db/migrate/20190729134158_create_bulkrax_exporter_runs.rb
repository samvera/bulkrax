class CreateBulkraxExporterRuns < ActiveRecord::Migration[5.1]
  def change
    create_table :bulkrax_exporter_runs do |t|
      t.references :exporter, foreign_key: { to_table: :bulkrax_exporters }
      t.integer :total_records, default: 0
      t.integer :enqueued_records, default: 0
      t.integer :processed_records, default: 0
      t.integer :deleted_records, default: 0
      t.integer :failed_records, default: 0
    end
  end
end
