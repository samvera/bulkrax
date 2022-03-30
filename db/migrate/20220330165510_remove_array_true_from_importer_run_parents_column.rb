class RemoveArrayTrueFromImporterRunParentsColumn < ActiveRecord::Migration[5.2]
  def change
    change_column :bulkrax_importer_runs, :parents, :text, array: false, default: nil
  end
end
