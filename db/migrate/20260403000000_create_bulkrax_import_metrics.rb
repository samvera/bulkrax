# frozen_string_literal: true

class CreateBulkraxImportMetrics < ActiveRecord::Migration[5.1]
  def change
    create_table :bulkrax_import_metrics do |t|
      t.string     :metric_type,   null: false
      t.string     :event,         null: false
      t.references :importer,      foreign_key: { to_table: :bulkrax_importers }, null: true
      t.references :user,          foreign_key: false, null: true
      t.string     :session_id
      t.jsonb      :payload,       default: {}
      t.timestamps
    end

    add_index :bulkrax_import_metrics, :metric_type
    add_index :bulkrax_import_metrics, :event
    add_index :bulkrax_import_metrics, :created_at
    add_index :bulkrax_import_metrics, [:metric_type, :created_at]
  end
end
