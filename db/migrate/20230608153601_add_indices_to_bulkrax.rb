class AddIndicesToBulkrax < ActiveRecord::Migration[5.1]
  def change
    add_index :bulkrax_entries, :identifier
    add_index :bulkrax_entries, :type
    add_index :bulkrax_entries, [:importerexporter_id, :importerexporter_type], name: 'bulkrax_entries_importerexporter_idx'

    add_index :bulkrax_pending_relationships, :parent_id
    add_index :bulkrax_pending_relationships, :child_id

    add_index :bulkrax_statuses, [:statusable_id, :statusable_type], name: 'bulkrax_statuses_statusable_idx'
    add_index :bulkrax_statuses, [:runnable_id, :runnable_type], name: 'bulkrax_statuses_runnable_idx'
    add_index :bulkrax_statuses, :error_class
  end
end
