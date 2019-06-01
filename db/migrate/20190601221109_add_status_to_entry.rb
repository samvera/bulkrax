class AddStatusToEntry < ActiveRecord::Migration[5.1]
  def change
    add_column :bulkrax_entries, :last_error, :text
    add_column :bulkrax_entries, :last_error_at, :datetime
    add_column :bulkrax_entries, :last_succeeded_at, :datetime
  end
end
