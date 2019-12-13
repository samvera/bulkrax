# frozen_string_literal: true

class AddOrcidToUsers < ActiveRecord::Migration[5.1]
  def change
    add_column :users, :orcid, :string
  end
end
