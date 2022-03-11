class CreateBulkraxPendingRelationships < ActiveRecord::Migration[5.2]
  def change
    create_table :bulkrax_pending_relationships do |t|
      t.belongs_to :bulkrax_importer_run, foreign_key: true, null: false
      t.string :parent_id, null: false
      t.string :child_id, null: false

      t.timestamps
    end
  end
end
