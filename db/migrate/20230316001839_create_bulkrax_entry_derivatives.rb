class CreateBulkraxEntryDerivatives < ActiveRecord::Migration[5.1]
  def change
    unless table_exists?(:bulkrax_entry_derivatives)
      create_table :bulkrax_entry_derivatives do |t|
        t.belongs_to :entry, foreign_key: true, null: false
        t.string :derivative_type, null: false
        t.text :path, null: false

        t.timestamps
      end
    end
  end
end
