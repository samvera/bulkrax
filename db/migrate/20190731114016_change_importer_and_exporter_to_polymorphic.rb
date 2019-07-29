class ChangeImporterAndExporterToPolymorphic < ActiveRecord::Migration[5.1]
  def change
    remove_reference :bulkrax_entries, :importer
    add_reference :bulkrax_entries, :importerexporter, polymorphic: true, index: {:name => "index_bulkrax_entries_on_importerexporter_type_and_id"}
  end
end
