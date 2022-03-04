class AddOrderToBulkraxPendingRelationships < ActiveRecord::Migration[5.2]
  def change
    add_column :bulkrax_pending_relationships, :order, :integer
  end
end
