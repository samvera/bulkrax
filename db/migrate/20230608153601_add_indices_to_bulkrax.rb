class AddIndicesToBulkrax < ActiveRecord::Migration[5.1]
  def change
    begin
      add_index :bulkrax_entries, :identifier
    rescue => e
      Rails.logger.info("Encountered #{e}; moving on.")
    end
    begin
      add_index :bulkrax_entries, :type
    rescue => e
      Rails.logger.info("Encountered #{e}; moving on.")
    end
    begin
      add_index :bulkrax_entries, [:importerexporter_id, :importerexporter_type], name: 'bulkrax_entries_importerexporter_idx'
    rescue => e
      Rails.logger.info("Encountered #{e}; moving on.")
    end
    begin
      add_index :bulkrax_pending_relationships, :parent_id
    rescue => e
      Rails.logger.info("Encountered #{e}; moving on.")
    end
    begin
      add_index :bulkrax_pending_relationships, :child_id
    rescue => e
      Rails.logger.info("Encountered #{e}; moving on.")
    end
    begin
      add_index :bulkrax_statuses, [:statusable_id, :statusable_type], name: 'bulkrax_statuses_statusable_idx'
    rescue => e
      Rails.logger.info("Encountered #{e}; moving on.")
    end
    begin
      add_index :bulkrax_statuses, [:runnable_id, :runnable_type], name: 'bulkrax_statuses_runnable_idx'
    rescue => e
      Rails.logger.info("Encountered #{e}; moving on.")
    end
    begin
      add_index :bulkrax_statuses, :error_class
    rescue => e
      Rails.logger.info("Encountered #{e}; moving on.")
    end
  end
end
