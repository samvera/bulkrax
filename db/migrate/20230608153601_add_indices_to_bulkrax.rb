class AddIndicesToBulkrax < ActiveRecord::Migration[5.1]
  def change
    check_and_add_index :bulkrax_entries, :identifier
    check_and_add_index :bulkrax_entries, :type
    check_and_add_index :bulkrax_entries, [:importerexporter_id, :importerexporter_type], name: 'bulkrax_entries_importerexporter_idx'
    check_and_add_index :bulkrax_pending_relationships, :child_id
    check_and_add_index :bulkrax_pending_relationships, :parent_id
    check_and_add_index :bulkrax_statuses, :error_class
    check_and_add_index :bulkrax_statuses, [:runnable_id, :runnable_type], name: 'bulkrax_statuses_runnable_idx'
    check_and_add_index :bulkrax_statuses, [:statusable_id, :statusable_type], name: 'bulkrax_statuses_statusable_idx'
  end

  def check_and_add_index(table_name, column_name, options = {})
    add_index(table_name, column_name, options) unless index_exists?(table_name, column_name, options)
  end
end
