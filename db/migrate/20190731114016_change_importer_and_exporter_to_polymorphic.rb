module Bulkrax
  class Entry < ApplicationRecord
     belongs_to :importer
  end
end

class ChangeImporterAndExporterToPolymorphic < ActiveRecord::Migration[5.1]
  def change
    rename_column :bulkrax_entries, :importer_id, :importerexporter_id if column_exists?(:bulkrax_entries, :importer_id)
    add_column :bulkrax_entries, :importerexporter_type, :string, after: :id, default: 'Bulkrax::Importer' unless column_exists?(:bulkrax_entries, :importerexporter_type)
  end
end
