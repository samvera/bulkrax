class CreateBulkraxImporterRuns < ActiveRecord::Migration[5.1]
  def change
    create_table :bulkrax_importer_runs do |t|
      t.references :importer, foreign_key: {to_table: :bulkrax_importers}
      t.integer :total_records, default: 0
      t.integer :enqueued_records, default: 0
      t.integer :processed_records, default: 0
      t.integer :deleted_records, default: 0
      t.integer :failed_records, default: 0

      t.timestamps
    end
  end
end
