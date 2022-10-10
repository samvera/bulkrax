class CreateSite < ActiveRecord::Migration[5.1]
  def change
    create_table :sites do |t|
      t.integer :account_id
    end
  end
end
