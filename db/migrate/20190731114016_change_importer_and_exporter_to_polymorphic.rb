class ChangeImporterAndExporterToPolymorphic < ActiveRecord::Migration[5.1]
  def change
    add_column :bulkrax_entries, :importerexporter_id, :integer
    add_column :bulkrax_entries, :importerexporter_type, :string, after: :id, default: 'Bulkrax::Importer'
    
    Bulkrax::Entry.reset_column_information
    Bulkrax::Entry.includes(:importer).find_each do | entry |
      entry.update_attribute(:importerexporter_id, entry.importer_id)
    end

    remove_column :bulkrax_entries, :importer_id
  end
end
