class AddOrcidToUsers < ActiveRecord::Migration[5.1]
  def change
    add_column :users, :orcid, :string
  end
end
