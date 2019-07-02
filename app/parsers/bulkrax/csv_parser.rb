module Bulkrax
  class CsvParser < ApplicationParser
    delegate :errors, to: :importer

    def self.parser_fields
      {
        csv_path: :string,
        rights_statements: :string,
        override_rights_statement: :boolean
      }
    end

    def initialize(importer)
      super
    end

    def records(_opts = {})
      csv = CSV.open(
        importer.parser_fields['csv_path'],
        headers: true,
        header_converters: :symbol,
        encoding: 'utf-8'
      )
      csv_data = csv.read
      raise StandardError, 'Identifier column is required' if csv_data.headers.include?(:identifier) == false

      # skip rows without an identifier; remove any nil values with compact
      csv_data.map { |row| row.to_h.compact! unless row[:identifier].blank? }.reject(&:blank?)
    rescue StandardError => e
      errors.add(:base, e.class.to_s.to_sym, message: e.message)
      []
    end

    def run
      create_works
    end

    def create_works
      records.each_with_index do |record, index|
        break if !limit.nil? && index >= limit

        seen[record[:identifier]] = true
        new_entry = entry_class.where(importer: importer, identifier: record[:identifier], raw_metadata: record).first_or_create!
        ImportWorkJob.perform_later(new_entry.id, importer.current_importer_run.id)
        importer.increment_counters(index)
      end
    end

    def files_path
      arr = importer.parser_fields['csv_path'].split('/')
      arr.pop
      arr << 'files'
      arr.join('/')
    end

    def entry_class
      CsvEntry
    end

    def total
      @total ||= records.count
    rescue StandardError
      @total = 0
    end
  end
end
