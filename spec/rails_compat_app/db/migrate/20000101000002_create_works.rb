# frozen_string_literal: true

class CreateWorks < ActiveRecord::Migration[7.0]
  def change
    create_table :works do |t|
      t.string :bulkrax_identifier
      t.string :title
      t.json :creator
      t.string :visibility
      t.json :member_ids
      t.timestamps
    end
  end
end
