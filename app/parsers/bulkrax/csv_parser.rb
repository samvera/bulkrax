# frozen_string_literal: true

require 'csv'
module Bulkrax
  class CsvParser < ApplicationParser
    include ErroredEntries
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
      # data for entry does not need source_identifier for csv, because csvs are read sequentially and mapped after raw data is read.
      @records ||= entry_class.read_data(file_for_import).map { |record_data| entry_class.data_for_entry(record_data, nil) }
    end

    # We could use CsvEntry#fields_from_data(data) but that would mean re-reading the data
    def import_fields
      @import_fields ||= records.inject(:merge).keys.compact.uniq
    end

    def required_elements?(keys)
      return unless keys.present?
      !missing_elements(keys).present?
    end

    def missing_elements(keys)
      required_elements.map(&:to_s) - keys.map(&:to_s)
    end

    def valid_import?
      error_alert = "Missing at least one required element, missing element(s) are: #{missing_elements(import_fields).join(', ')}"
      raise StandardError, error_alert unless required_elements?(import_fields)

      file_paths.is_a?(Array)
    rescue StandardError => e
      status_info(e)
      false
    end

    def create_collections
      collections.each_with_index do |collection, index|
        next if collection.blank?
        metadata = {
          title: [collection],
          work_identifier => [collection],
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
        next unless record_has_source_identifier(record, index)
        break if limit_reached?(limit, index)

        seen[record[source_identifier]] = true
        new_entry = find_or_create_entry(entry_class, record[source_identifier], 'Bulkrax::Importer', record.to_h.compact)
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
        entry_ids = importer.entries.pluck(:id)
        complete_statuses = Bulkrax::Status.latest_by_statusable
                                           .includes(:statusable)
                                           .where('bulkrax_statuses.statusable_id IN (?) AND bulkrax_statuses.statusable_type = ? AND status_message = ?', entry_ids, 'Bulkrax::Entry', 'Complete')
        complete_entry_identifiers = complete_statuses.map { |s| s.statusable&.identifier }

        ActiveFedora::SolrService.query("#{work_identifier}_tesim:(#{complete_entry_identifiers.join(' OR ')})#{extra_filters}", rows: 2_000_000_000).map(&:id)
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
        return @total if @total&.positive?
        # windows enocded
        @total = `grep -c ^M #{real_import_file_path}`.to_i - 1
        # unix encoded
        @total = `grep -vc ^$ #{real_import_file_path}`.to_i - 1 if @total < 1
      elsif exporter?
        @total = importerexporter.entries.count
      else
        @total = 0
      end
      return @total
    rescue StandardErrorr
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

    def key_allowed(key)
      !Bulkrax.reserved_properties.include?(key) &&
        new_entry(entry_class, 'Bulkrax::Exporter').field_supported?(key) &&
        key != source_identifier.to_s
    end

    # All possible column names
    def export_headers
      headers = ['id']
      headers << source_identifier.to_s
      headers << 'model'
      importerexporter.mapping.each_key { |key| headers << key if key_allowed(key) }
      headers << 'file'
      headers.uniq
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
