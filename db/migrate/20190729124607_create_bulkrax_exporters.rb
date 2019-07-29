class CreateBulkraxExporters < ActiveRecord::Migration[5.1]
  def change
    create_table :bulkrax_exporters do |t|
      t.string :name
#      t.string :admin_set_id
      t.references :user, foreign_key: false
#      t.string :frequency
      t.string :parser_klass
      t.integer :limit
#      t.text :parser_fields
      t.text :field_mapping
      t.string :export_source
      t.string :export_from
      t.string :export_type

      t.timestamps
    end
  end
end
