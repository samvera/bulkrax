class AddInheritParentVisibilityToBulkraxPendingRelationships < ActiveRecord::Migration[5.2]
  def change
    add_column :bulkrax_pending_relationships, :inherit_parent_visibility, :boolean, default: false, null: false unless column_exists?(:bulkrax_pending_relationships, :inherit_parent_visibility)
  end
end
