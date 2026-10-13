# frozen_string_literal: true

class CreateBulkraxImportMetrics < ActiveRecord::Migration[5.2]
  def change
    create_table :bulkrax_import_metrics do |t|
      t.string :metric_type, null: false
      t.string :event, null: false
      t.references :importer, foreign_key: false
      t.references :importer_run, foreign_key: false, index: false
      t.references :user, foreign_key: false
      t.string :session_id, index: true
      t.string :outcome
      t.boolean :first_attempt
      t.integer :duration_ms
      t.integer :step
      t.integer :rating
      t.text :payload
      t.timestamps
    end

    add_index :bulkrax_import_metrics, [:metric_type, :created_at]
    add_index :bulkrax_import_metrics, [:importer_run_id, :metric_type], unique: true, name: 'index_bulkrax_import_metrics_on_run_and_type'
  end
end
