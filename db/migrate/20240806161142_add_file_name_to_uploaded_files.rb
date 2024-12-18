class AddFileNameToUploadedFiles < ActiveRecord::Migration[5.2]
  def change
    add_column :uploaded_files, :filename, :string if table_exists?(:uploaded_files) && !column_exists?(:uploaded_files, :filename)
  end
end
