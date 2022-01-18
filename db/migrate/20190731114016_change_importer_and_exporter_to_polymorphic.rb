module Bulkrax
  class Entry < ApplicationRecord
     belongs_to :importer
  end
end

class ChangeImporterAndExporterToPolymorphic < ActiveRecord::Migration[5.1]
  def change
    if column_exists?(:bulkrax_entries, :importer_id)
      remove_foreign_key :bulkrax_entries, column: :importer_id
      remove_index :bulkrax_entries, :importer_id
      rename_column :bulkrax_entries, :importer_id, :importerexporter_id
    end
    add_column :bulkrax_entries, :importerexporter_type, :string, after: :id, default: 'Bulkrax::Importer' unless column_exists?(:bulkrax_entries, :importerexporter_type)
  end
end
