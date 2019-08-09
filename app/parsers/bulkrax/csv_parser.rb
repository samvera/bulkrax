module Bulkrax
  class CsvParser < ApplicationParser
    delegate :errors, :increment_counters, :parser_fields, to: :importer

    def records(_opts = {})
      # there's a risk that this reads the whole file into memory and could cause a memory leak
      @records ||= CSV.foreach(
        parser_fields['csv_path'],
        headers: true,
        header_converters: :symbol,
        encoding: 'utf-8'
      )
    end

    def import_fields
      @import_fields ||= records.map {|r| r.headers }.flatten
    end

    def create_collections
      # does the CSV contain a collection column?
      return unless import_fields.include?(:collection)

      # retrieve a list of unique collections
      collections = records.map { |r| r[:collection] }.compact.uniq

      collections.each do |collection_record|
        next if collection_record.blank?

        # split by ; |
        collection_record.split(/\s*[;|]\s*/).each do |collection|
          metadata = {
            title: [collection],
            Bulkrax.system_identifier_field => [collection],
            visibility: 'open',
            collection_type_gid: Hyrax::CollectionType.find_or_create_default_collection_type.gid
          }
          new_entry = collection_entry_class.where(importer: importer, identifier: collection, raw_metadata: metadata).first_or_create!
          ImportWorkCollectionJob.perform_later(new_entry.id, importer.current_importer_run.id)
        end
      end
    end

    def create_works
      records.with_index(0) do |record, index|
        next if record[:source_identifier].blank?
        break if !limit.nil? && index >= limit

        seen[record[:source_identifier]] = true
        new_entry = entry_class.where(importer: importer, identifier: record[:source_identifier], raw_metadata: record.to_h.compact).first_or_create!
        ImportWorkJob.perform_later(new_entry.id, importer.current_importer_run.id)
        increment_counters(index)
      end
    rescue StandardError => e
      errors.add(:base, e.class.to_s.to_sym, message: e.message)
    end

    def files_path
      arr = parser_fields['csv_path'].split('/')
      arr.pop
      arr << 'files'
      arr.join('/')
    end

    def entry_class
      CsvEntry
    end

    def collection_entry_class
      CsvCollectionEntry
    end

    # See https://stackoverflow.com/questions/2650517/count-the-number-of-lines-in-a-file-without-reading-entire-file-into-memory
    def total
      @total ||= `wc -l #{parser_fields['csv_path']}`.to_i -1
    rescue StandardError
      @total = 0
    end
  end
end
