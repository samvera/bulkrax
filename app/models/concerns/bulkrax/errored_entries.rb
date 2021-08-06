# frozen_string_literal: true

module Bulkrax
  module ErroredEntries
    extend ActiveSupport::Concern

    def write_errored_entries_file
      if @errored_entries.blank?
        entry_ids = importerexporter.entries.pluck(:id)
        error_statuses = Bulkrax::Status.latest_by_statusable
                                        .includes(:statusable)
                                        .where('bulkrax_statuses.statusable_id IN (?) AND bulkrax_statuses.statusable_type = ? AND status_message = ?', entry_ids, 'Bulkrax::Entry', 'Failed')
        @errored_entries = error_statuses.map(&:statusable)
      end
      return unless @errored_entries.present?

      file = setup_errored_entries_file
      headers = import_fields
      file.puts(headers.to_csv)
      @errored_entries.each do |ee|
        row = build_errored_entry_row(headers, ee)
        file.puts(row)
      end
      file.close
      true
    end

    def build_errored_entry_row(headers, errored_entry)
      row = {}
      # Ensure each header has a value, even if it's just an empty string
      headers.each do |h|
        row.merge!("#{h}": nil)
      end
      # Match each value to its corresponding header
      row.merge!(errored_entry.raw_metadata.symbolize_keys)

      row.values.to_csv
    end

    def setup_errored_entries_file
      FileUtils.mkdir_p(File.dirname(importerexporter.errored_entries_csv_path))
      File.open(importerexporter.errored_entries_csv_path, 'w')
    end
  end
end
