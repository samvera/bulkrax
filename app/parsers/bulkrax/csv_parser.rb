module Bulkrax
  class CsvParser < ApplicationParser

    def self.parser_fields
      {
        csv_path: :string,
        rights_statements: :string,
        override_rights_statement: :boolean
      }
    end

    def self.export_supported?
      true
    end

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
      return if import_fields.map {|r| r.headers.include?(:collection) }.blank?

      records.each do |record|
        next if record[:collection].blank?

        # split by : ; |
        record[:collection].split(/\s*[:;|]\s*/).each do |collection|
          metadata = {
            title: [collection],
            Bulkrax.system_identifier_field => [collection],
            visibility: 'open',
            collection_type_gid: Hyrax::CollectionType.find_or_create_default_collection_type.gid
          }
          new_entry = find_or_create_entry(collection_entry_class, collection, 'Bulkrax::Importer', metadata)
          ImportWorkCollectionJob.perform_later(new_entry.id, current_importer_run.id)
        end
      end
    end

    def create_works
      records.with_index(0) do |record, index|
        next if record[:source_identifier].blank?
        break if !limit.nil? && index >= limit

        seen[record[:source_identifier]] = true
        new_entry = find_or_create_entry(entry_class, record[:source_identifier], 'Bulkrax::Importer', record.to_h.compact)
        ImportWorkJob.perform_later(new_entry.id, current_importer_run.id)
        increment_counters(index)
      end
    rescue StandardError => e
      errors.add(:base, e.class.to_s.to_sym, message: e.message)
    end

    def create_from_importer
      importer = Bulkrax::Importer.find(importerexporter.export_source)
      importer.entries.each do | entry |
        query = "#{ActiveFedora.index_field_mapper.solr_name(Bulkrax.system_identifier_field)}:\"#{entry.identifier}\""
        work_id = ActiveFedora::SolrService.query(query, fl: 'id', rows: 1).first['id']
        new_entry = find_or_create_entry(entry_class, work_id, 'Bulkrax::Exporter')
        Bulkrax::ExportWorkJob.perform_now(new_entry.id,  current_exporter_run.id)
      end
    end

    def create_from_collection
      work_ids = ActiveFedora::SolrService.query("member_of_collection_ids_ssim:#{importerexporter.export_source}").map(&:id)
      work_ids.each do | wid |
        new_entry = find_or_create_entry(entry_class, wid, 'Bulkrax::Exporter')
        Bulkrax::ExportWorkJob.perform_now(new_entry.id,  current_exporter_run.id)
      end
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
      if importer?
        @total ||= `wc -l #{parser_fields['csv_path']}`.to_i -1
      elsif exporter?
        @total ||= importerexporter.entries.count
      else
        @total = 0
      end
    rescue StandardError
      @total = 0
    end

    # export methods

    def write_files
      file = setup_export_file
      file.puts(export_headers)
      importerexporter.entries.each do | e |
        file.puts(e.parsed_metadata.values.to_csv)
      end
      file.close
    end

    def export_headers
      headers = ['id']
      headers = ['model']
      importerexporter.mapping.keys.each {|key| headers << key unless Bulkrax.reserved_properties.include?(key) && !field_supported?(key)}.sort
      headers << 'file'
      headers.to_csv
    end

    # in the parser as it is specific to the format
    def setup_export_file
      File.open(File.join(importerexporter.exporter_export_path, 'export.csv'), 'w')
    end

  end
end
