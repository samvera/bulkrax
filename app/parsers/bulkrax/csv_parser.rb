# frozen_string_literal: true

require 'csv'
module Bulkrax
  class CsvParser < ApplicationParser
    def self.export_supported?
      true
    end

    def initialize(importerexporter)
      @importerexporter = importerexporter
    end

    def collections
      # does the CSV contain a collection column?
      return [] unless import_fields.include?(:collection)
      # retrieve a list of unique collections
      records.map { |r| r[:collection].split(/\s*[;|]\s*/) unless r[:collection].blank? }.flatten.compact.uniq
    end

    def collections_total
      collections.size
    end

    def records(_opts = {})
      file_for_import = only_updates ? parser_fields['partial_import_file_path'] : import_file_path
      @records ||= entry_class.read_data(file_for_import).map { |record_data| entry_class.data_for_entry(record_data) }
    end

    # We could use CsvEntry#fields_from_data(data) but that would mean re-reading the data
    def import_fields
      @import_fields ||= records.inject(:merge).keys.compact.uniq
    end

    def required_elements?(keys)
      return if keys.blank?
      !required_elements.map { |el| keys.map(&:to_s).include?(el) }.include?(false)
    end

    def valid_import?
      required_elements?(import_fields) && file_paths.is_a?(Array)
    rescue StandardError => e
      status_info(e)
      false
    end

    def create_collections
      collections.each_with_index do |collection, index|
        next if collection.blank?
        metadata = {
          title: [collection],
          Bulkrax.system_identifier_field => [collection],
          visibility: 'open',
          collection_type_gid: Hyrax::CollectionType.find_or_create_default_collection_type.gid
        }
        new_entry = find_or_create_entry(collection_entry_class, collection, 'Bulkrax::Importer', metadata)
        ImportWorkCollectionJob.perform_now(new_entry.id, current_run.id)
        increment_counters(index, true)
      end
    end

    def create_works
      records.each_with_index do |record, index|
        if record[source_identifier_symbol].blank?
          invalid_record("Missing #{source_identifier_symbol} for #{record.to_h}\n")
          next
        end
        break if limit_reached?(limit, index)

        seen[record[source_identifier_symbol]] = true
        new_entry = find_or_create_entry(entry_class, record[source_identifier_symbol], 'Bulkrax::Importer', record.to_h.compact)
        if record[:delete].present?
          DeleteWorkJob.send(perform_method, new_entry, current_run)
        else
          ImportWorkJob.send(perform_method, new_entry.id, current_run.id)
        end
        increment_counters(index)
      end
      importer.record_status
    rescue StandardError => e
      status_info(e)
    end

    def write_partial_import_file(file)
      import_filename = import_file_path.split('/').last
      partial_import_filename = "#{File.basename(import_filename, '.csv')}_corrected_entries.csv"

      path = File.join(path_for_import, partial_import_filename)
      FileUtils.mv(
        file.path,
        path
      )
      path
    end

    def create_parent_child_relationships
      super
    end

    def extra_filters
      output = ""
      if importerexporter.start_date.present?
        start_dt = importerexporter.start_date.to_datetime.strftime('%FT%TZ')
        finish_dt = importerexporter.finish_date.present? ? importerexporter.finish_date.to_datetime.end_of_day.strftime('%FT%TZ') : "NOW"
        output += " AND system_modified_dtsi:[#{start_dt} TO #{finish_dt}]"
      end
      output += importerexporter.work_visibility.present? ? " AND visibility_ssi:#{importerexporter.work_visibility}" : ""
      output += importerexporter.workflow_status.present? ? " AND workflow_state_name_ssim:#{importerexporter.workflow_status}" : ""
      output
    end

    def current_work_ids
      case importerexporter.export_from
      when 'collection'
        ActiveFedora::SolrService.query("member_of_collection_ids_ssim:#{importerexporter.export_source + extra_filters}", rows: 2_000_000_000).map(&:id)
      when 'worktype'
        ActiveFedora::SolrService.query("has_model_ssim:#{importerexporter.export_source + extra_filters}", rows: 2_000_000_000).map(&:id)
      when 'importer'
        importer = Bulkrax::Importer.find(importerexporter.export_source)
        # TODO: this seems likely to be broken
        entry_ids = importer.entries.where(type: importer.parser.entry_class.to_s, last_error: [nil, {}, '']).map(&:identifier)
        ActiveFedora::SolrService.query("#{Bulkrax.system_identifier_field}_tesim:(#{entry_ids.join(' OR ')})#{extra_filters}", rows: 2_000_000_000).map(&:id)
      end
    end

    def create_new_entries
      current_work_ids.each_with_index do |wid, index|
        break if limit_reached?(limit, index)
        new_entry = find_or_create_entry(entry_class, wid, 'Bulkrax::Exporter')
        Bulkrax::ExportWorkJob.perform_now(new_entry.id, current_run.id)
      end
    end
    alias create_from_collection create_new_entries
    alias create_from_importer create_new_entries
    alias create_from_worktype create_new_entries

    def entry_class
      CsvEntry
    end

    def collection_entry_class
      CsvCollectionEntry
    end

    # See https://stackoverflow.com/questions/2650517/count-the-number-of-lines-in-a-file-without-reading-entire-file-into-memory
    #   Changed to grep as wc -l counts blank lines, and ignores the final unescaped line (which may or may not contain data)
    def total
      if importer?
        # windows enocded
        @total ||= `grep -c ^M #{real_import_file_path}`.to_i - 1
        # @total ||= `wc -l #{parser_fields['import_file_path']}`.to_i - 1
        # unix encoded
        @total ||= `grep -vc ^$ #{real_import_file_path}`.to_i - 1 if @total < 1
      elsif exporter?
        @total ||= importerexporter.entries.count
      else
        @total = 0
      end
    rescue StandardError
      @total = 0
    end

    # @todo - investigate getting directory structure
    # @todo - investigate using perform_later, and having the importer check for
    #   DownloadCloudFileJob before it starts
    def retrieve_cloud_files(files)
      files_path = File.join(path_for_import, 'files')
      FileUtils.mkdir_p(files_path) unless File.exist?(files_path)
      files.each_pair do |_key, file|
        # fixes bug where auth headers do not get attached properly
        if file['auth_header'].present?
          file['headers'] ||= {}
          file['headers'].merge!(file['auth_header'])
        end
        # this only works for uniquely named files
        target_file = File.join(files_path, file['file_name'].tr(' ', '_'))
        # Now because we want the files in place before the importer runs
        # Problematic for a large upload
        Bulkrax::DownloadCloudFileJob.perform_now(file, target_file)
      end
      return nil
    end

    # export methods

    def write_files
      CSV.open(setup_export_file, "w", headers: export_headers, write_headers: true) do |csv|
        importerexporter.entries.where(identifier: current_work_ids)[0..limit || total].each do |e|
          csv << e.parsed_metadata
        end
      end
    end

    # All possible column names
    def export_headers
      headers = ['id']
      headers << entry_class.source_identifier_field
      headers << 'model'
      importerexporter.mapping.each_key { |key| headers << key unless Bulkrax.reserved_properties.include?(key) && !field_supported?(key) }.sort
      headers << 'file'
      headers
    end

    # in the parser as it is specific to the format
    def setup_export_file
      File.join(importerexporter.exporter_export_path, 'export.csv')
    end

    # Retrieve file paths for [:file] mapping in records
    #  and check all listed files exist.
    def file_paths
      raise StandardError, 'No records were found' if records.blank?
      @file_paths ||= records.map do |r|
        file_mapping = Bulkrax.field_mappings.dig(self.class.to_s, 'file', :from)&.first&.to_sym || :file
        next unless r[file_mapping].present?

        r[file_mapping].split(/\s*[:;|]\s*/).map do |f|
          file = File.join(path_to_files, f.tr(' ', '_'))
          if File.exist?(file) # rubocop:disable Style/GuardClause
            file
          else
            raise "File #{file} does not exist"
          end
        end
      end.flatten.compact.uniq
    end

    # Retrieve the path where we expect to find the files
    def path_to_files
      @path_to_files ||= File.join(
        File.file?(import_file_path) ? File.dirname(import_file_path) : import_file_path,
        'files'
      )
    end

    # errored entries methods

    def write_errored_entries_file
      @errored_entries ||= importerexporter.entries.where.not(last_error: [nil, {}, ''], type: 'Bulkrax::CsvCollectionEntry')
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

    private

      # Override to return the first CSV in the path, if a zip file is supplied
      # We expect a single CSV at the top level of the zip in the CSVParser
      # but we are willing to go look for it if need be
      def real_import_file_path
        if file? && zip?
          unzip(parser_fields['import_file_path'])
          return Dir["#{importer_unzip_path}/**/*.csv"].first
        else
          parser_fields['import_file_path']
        end
      end
  end
end
