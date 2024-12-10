class AddFileNameToUploadedFiles < ActiveRecord::Migration[5.2]
  def change
    if table_exists?(:uploaded_files)
      add_column :uploaded_files, :filename, :string unless column_exists?(:uploaded_files, :filename)
    end
  end
end
