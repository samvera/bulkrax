class ChangeCollectionIdsOnEntries < ActiveRecord::Migration[5.1]
  def change
    rename_column :bulkrax_entries, :collection_id, :collection_ids
  end
end
