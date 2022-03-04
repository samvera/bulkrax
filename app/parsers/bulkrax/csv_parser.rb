# frozen_string_literal: true

require 'csv'
module Bulkrax
  class CsvParser < ApplicationParser # rubocop:disable Metrics/ClassLength
    include ErroredEntries
    def self.export_supported?
      true
    end

    def records(_opts = {})
      file_for_import = only_updates ? parser_fields['partial_import_file_path'] : import_file_path
      # data for entry does not need source_identifier for csv, because csvs are read sequentially and mapped after raw data is read.
      csv_data = entry_class.read_data(file_for_import)
      importer.parser_fields['total'] = csv_data.count
      importer.save
      @records ||= csv_data.map { |record_data| entry_class.data_for_entry(record_data, nil) }
    end

    def collections
      ActiveSupport::Deprecation.warn(
        'Creating Collections using the collection_field_mapping will no longer be supported as of Bulkrax version 3.0.' \
        ' Please configure Bulkrax to use related_parents_field_mapping and related_children_field_mapping instead.'
      )
      # retrieve a list of unique collections
      records.map do |r|
        collections = []
        r[collection_field_mapping].split(/\s*[;|]\s*/).each { |title| collections << { title: title, from_collection_field_mapping: true } } if r[collection_field_mapping].present?
        model_field_mappings.each do |model_mapping|
          collections << r if r[model_mapping.to_sym]&.downcase == 'collection'
        end
        collections
      end.flatten.compact.uniq
    end

    def collections_total
      collections.size
    end

    def works
      records - collections - file_sets
    end

    def works_total
      works.size
    end

    def file_sets
      records.map do |r|
        file_sets = []
        model_field_mappings.each do |model_mapping|
          file_sets << r if r[model_mapping.to_sym]&.downcase == 'fileset'
        end
        file_sets
      end.flatten.compact.uniq
    end

    def file_sets_total
      file_sets.size
    end

    # We could use CsvEntry#fields_from_data(data) but that would mean re-reading the data
    def import_fields
      @import_fields ||= records.inject(:merge).keys.compact.uniq
    end

    def required_elements?(keys)
      return if keys.blank?
      missing_elements(keys).blank?
    end

    def missing_elements(keys)
      required_elements.map(&:to_s) - keys.map(&:to_s)
    end

    def valid_import?
      import_strings = keys_without_numbers(import_fields.map(&:to_s))
      error_alert = "Missing at least one required element, missing element(s) are: #{missing_elements(import_strings).join(', ')}"
      raise StandardError, error_alert unless required_elements?(import_strings)

      file_paths.is_a?(Array)
    rescue StandardError => e
      status_info(e)
      false
    end

    def create_collections
      collections.each_with_index do |collection, index|
        next if collection.blank?
        break if records.find_index(collection).present? && limit_reached?(limit, records.find_index(collection))
        ActiveSupport::Deprecation.warn(
          'Creating Collections using the collection_field_mapping will no longer be supported as of Bulkrax version 3.0.' \
          ' Please configure Bulkrax to use related_parents_field_mapping and related_children_field_mapping instead.'
        )

        ## BEGIN
        # Add required metadata to collections being imported using the collection_field_mapping, which only have a :title
        # TODO: Remove once collection_field_mapping is removed
        metadata = if collection.delete(:from_collection_field_mapping)
                     uci = unique_collection_identifier(collection)
                     {
                       title: collection[:title],
                       work_identifier => uci,
                       source_identifier => uci,
                       visibility: 'open',
                       collection_type_gid: ::Hyrax::CollectionType.find_or_create_default_collection_type.gid
                     }
                   end
        collection_hash = metadata.presence || collection
        ## END

        new_entry = find_or_create_entry(collection_entry_class, collection_hash[source_identifier], 'Bulkrax::Importer', collection_hash)
        increment_counters(index, collection: true)
        # TODO: add support for :delete option
        ImportCollectionJob.perform_now(new_entry.id, current_run.id)
      end
      importer.record_status
    rescue StandardError => e
      status_info(e)
    end

    def create_works
      works.each_with_index do |work, index|
        next unless record_has_source_identifier(work, records.find_index(work))
        break if limit_reached?(limit, records.find_index(work))

        seen[work[source_identifier]] = true
        new_entry = find_or_create_entry(entry_class, work[source_identifier], 'Bulkrax::Importer', work.to_h)
        if work[:delete].present?
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

    def create_file_sets
      file_sets.each_with_index do |file_set, index|
        next unless record_has_source_identifier(file_set, records.find_index(file_set))
        break if limit_reached?(limit, records.find_index(file_set))

        new_entry = find_or_create_entry(file_set_entry_class, file_set[source_identifier], 'Bulkrax::Importer', file_set.to_h)
        ImportFileSetJob.perform_later(new_entry.id, current_run.id)
        increment_counters(index, file_set: true)
      end
      importer.record_status
    rescue StandardError => e
      status_info(e)
    end

    def create_relationships
      ScheduleRelationshipsJob.set(wait: 1.minutes).perform_later(importer_id: importerexporter.id)
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
      ActiveSupport::Deprication.warn('Bulkrax::CsvParser#current_work_ids will be replaced with #current_record_ids in version 3.0')
      current_record_ids
    end

    def current_record_ids
      @work_ids = []
      @collection_ids = []
      @file_set_ids = []

      case importerexporter.export_from
      when 'all'
        @work_ids = ActiveFedora::SolrService.query("has_model_ssim:(#{Hyrax.config.curation_concerns.join(' OR ')}) #{extra_filters}", rows: 2_147_483_647).map(&:id)
        @collection_ids = ActiveFedora::SolrService.query("has_model_ssim:Collection #{extra_filters}", rows: 2_147_483_647).map(&:id)
        @file_set_ids = ActiveFedora::SolrService.query("has_model_ssim:FileSet #{extra_filters}", rows: 2_147_483_647).map(&:id)
      when 'collection'
        @work_ids = ActiveFedora::SolrService.query("member_of_collection_ids_ssim:#{importerexporter.export_source + extra_filters}", rows: 2_000_000_000).map(&:id)
      when 'worktype'
        @work_ids = ActiveFedora::SolrService.query("has_model_ssim:#{importerexporter.export_source + extra_filters}", rows: 2_000_000_000).map(&:id)
      when 'importer'
        set_ids_for_exporting_from_importer
      end

      @work_ids + @collection_ids + @file_set_ids
    end

    # Set the following instance variables: @work_ids, @collection_ids, @file_set_ids
    # @see #current_record_ids
    def set_ids_for_exporting_from_importer
      entry_ids = Importer.find(importerexporter.export_source).entries.pluck(:id)
      complete_statuses = Status.latest_by_statusable
                                .includes(:statusable)
                                .where('bulkrax_statuses.statusable_id IN (?) AND bulkrax_statuses.statusable_type = ? AND status_message = ?', entry_ids, 'Bulkrax::Entry', 'Complete')

      complete_entry_identifiers = complete_statuses.map { |s| s.statusable&.identifier&.gsub(':', '\:') }
      extra_filters = extra_filters.presence || '*:*'

      { :@work_ids => ::Hyrax.config.curation_concerns, :@collection_ids => [::Collection], :@file_set_ids => [::FileSet] }.each do |instance_var, models_to_search|
        instance_variable_set(instance_var, ActiveFedora::SolrService.get(
          extra_filters.to_s,
          fq: [
            "#{work_identifier}_sim:(#{complete_entry_identifiers.join(' OR ')})",
            "has_model_ssim:(#{models_to_search.join(' OR ')})"
          ],
          fl: 'id',
          rows: 2_000_000_000
        )['response']['docs'].map { |obj| obj['id'] })
      end
    end

    def create_new_entries
      current_record_ids.each_with_index do |id, index|
        break if limit_reached?(limit, index)

        this_entry_class = if @collection_ids.include?(id)
                             collection_entry_class
                           elsif @file_set_ids.include?(id)
                             file_set_entry_class
                           else
                             entry_class
                           end
        new_entry = find_or_create_entry(this_entry_class, id, 'Bulkrax::Exporter')

        begin
          entry = ExportWorkJob.perform_now(new_entry.id, current_run.id)
        rescue => e
          Rails.logger.info("#{e.message} was detected during export")
        end

        self.headers |= entry.parsed_metadata.keys if entry
      end
    end
    alias create_from_collection create_new_entries
    alias create_from_importer create_new_entries
    alias create_from_worktype create_new_entries
    alias create_from_all create_new_entries

    def entry_class
      CsvEntry
    end

    def collection_entry_class
      CsvCollectionEntry
    end

    def file_set_entry_class
      CsvFileSetEntry
    end

    # See https://stackoverflow.com/questions/2650517/count-the-number-of-lines-in-a-file-without-reading-entire-file-into-memory
    #   Changed to grep as wc -l counts blank lines, and ignores the final unescaped line (which may or may not contain data)
    def total
      @total = importer.parser_fields['total'] || 0 if importer?
      @total = importerexporter.entries.count if exporter?

      return @total || 0
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
        importerexporter.entries.where(identifier: current_record_ids)[0..limit || total].each do |e|
          csv << e.parsed_metadata
        end
      end
    end

    def export_key_allowed(key)
      new_entry(entry_class, 'Bulkrax::Exporter').field_supported?(key) &&
        key != source_identifier.to_s
    end

    # All possible column names
    def export_headers
      headers = sort_headers(self.headers)

      # we don't want access_control_id exported and we want file at the end
      headers.delete('access_control_id') if headers.include?('access_control_id')

      # add the headers below at the beginning or end to maintain the preexisting export behavior
      headers.prepend('model')
      headers.prepend(source_identifier.to_s)
      headers.prepend('id')

      headers.uniq
    end

    def object_names
      return @object_names if @object_names

      @object_names = mapping.values.map { |value| value['object'] }
      @object_names.uniq!.delete(nil)

      @object_names
    end

    def sort_headers(headers)
      # converting headers like creator_name_1 to creator_1_name so they get sorted by numerical order
      # while keeping objects grouped together
      headers.sort_by do |item|
        number = item.match(/\d+/)&.[](0) || 0.to_s
        sort_number = number.rjust(4, "0")
        object_prefix = object_names.detect { |o| item.match(/^#{o}/) } || item
        remainder = item.gsub(/^#{object_prefix}_/, '').gsub(/_#{number}/, '')
        "#{object_prefix}_#{sort_number}_#{remainder}"
      end
    end

    # in the parser as it is specific to the format
    def setup_export_file
      File.join(importerexporter.exporter_export_path, "export_#{importerexporter.export_source}_from_#{importerexporter.export_from}.csv")
    end

    # Retrieve file paths for [:file] mapping in records
    #  and check all listed files exist.
    def file_paths
      raise StandardError, 'No records were found' if records.blank?
      return [] if importerexporter.metadata_only?

      @file_paths ||= records.map do |r|
        file_mapping = Bulkrax.field_mappings.dig(self.class.to_s, 'file', :from)&.first&.to_sym || :file
        next if r[file_mapping].blank?

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
        zip? ? importer_unzip_path : File.dirname(import_file_path),
        'files'
      )
    end

    private

    def unique_collection_identifier(collection_hash)
      entry_uid = collection_hash[source_identifier]
      entry_uid ||= if Bulkrax.fill_in_blank_source_identifiers.present?
                      Bulkrax.fill_in_blank_source_identifiers.call(self, records.find_index(collection_hash))
                    else
                      collection_hash[:title].split(/\s*[;|]\s*/).first
                    end

      entry_uid
    end

    # Override to return the first CSV in the path, if a zip file is supplied
    # We expect a single CSV at the top level of the zip in the CSVParser
    # but we are willing to go look for it if need be
    def real_import_file_path
      return Dir["#{importer_unzip_path}/**/*.csv"].first if file? && zip?

      parser_fields['import_file_path']
    end
  end
end
