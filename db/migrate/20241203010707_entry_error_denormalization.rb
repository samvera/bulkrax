class EntryErrorDenormalization < ActiveRecord::Migration[6.1]
  def change
    add_column :bulkrax_entries, :error_class, :string unless column_exists?(:bulkrax_entries, :error_class)
  end
end
