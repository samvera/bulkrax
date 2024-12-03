class EntryErrorDenormalization < ActiveRecord::Migration[6.1]
  def change
    add_column :bulkrax_entries, :error_class, :string unless column_exists?(:bulkrax_entries, :error_class)
    add_column :bulkrax_importers, :error_class, :string unless column_exists?(:bulkrax_entries, :error_class)
    add_column :bulkrax_exporters, :error_class, :string unless column_exists?(:bulkrax_entries, :error_class)
  end
end
