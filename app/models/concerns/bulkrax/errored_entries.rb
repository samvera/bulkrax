# frozen_string_literal: true

module Bulkrax
  module ErroredEntries
    extend ActiveSupport::Concern

    def errored_entries
      @errored_entries ||= importerexporter.entries.failed
    end

    def write_errored_entries_file
      return if errored_entries.blank?

      setup_errored_entries_file do |csv|
        errored_entries.find_each do |ee|
          csv << ee.raw_metadata
        end
      end
      true
    end

    def setup_errored_entries_file
      FileUtils.mkdir_p(File.dirname(importerexporter.errored_entries_csv_path))
      CSV.open(importerexporter.errored_entries_csv_path, 'wb', headers: import_fields.map(&:to_s), write_headers: true) do |csv|
        yield csv
      end
    end
  end
end
