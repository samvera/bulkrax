class ChangeBulkraxStatusesErrorMessageColumnTypeToText < ActiveRecord::Migration[5.1]
  def change
    change_column :bulkrax_statuses, :error_message, :text
  end
end
