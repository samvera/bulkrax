# frozen_string_literal: true

require 'csv'
module Bulkrax
  class CsvParser < ApplicationParser # rubocop:disable Metrics/ClassLength
    include ErroredEntries
    include ExportBehavior
    attr_writer :collections, :file_sets, :works

    def self.export_supported?
      true
    end

    def records(_opts = {})
      return @records if @records.present?

      file_for_import = only_updates ? parser_fields['partial_import_file_path'] : import_file_path
      # data for entry does not need source_identifier for csv, because csvs are read sequentially and mapped after raw data is read.
      csv_data = entry_class.read_data(file_for_import)
      importer.parser_fields['total'] = csv_data.count
      importer.save

      @records = csv_data.map { |record_data| entry_class.data_for_entry(record_data, nil, self) }
    end

    def build_records
      @collections = []
      @works = []
      @file_sets = []

      if model_field_mappings.map { |mfm| mfm.to_sym.in?(records.first.keys) }.any?
        records.map do |r|
          model_field_mappings.map(&:to_sym).each do |model_mapping|
            next unless r.key?(model_mapping)

            if r[model_mapping].casecmp('collection').zero?
              @collections << r
            elsif r[model_mapping].casecmp('fileset').zero?
              @file_sets << r
            else
              @works << r
            end
          end
        end
        @collections = @collections.flatten.compact.uniq
        @file_sets = @file_sets.flatten.compact.uniq
        @works = @works.flatten.compact.uniq
      else # if no model is specified, assume all records are works
        @works = records.flatten.compact.uniq
      end

      true
    end

    def collections
      build_records if @collections.nil?
      @collections
    end

    def works
      build_records if @works.nil?
      @works
    end

    def file_sets
      build_records if @file_sets.nil?
      @file_sets
    end

    def collections_total
      collections.size
    end

    def works_total
      works.size
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
      create_objects(['collection'])
    end

    def create_works
      create_objects(['work'])
    end

    def create_file_sets
      create_objects(['file_set'])
    end

    def create_relationships
      create_objects(['relationship'])
    end

    def create_objects(types_array = nil)
      index = 0
      (types_array || %w[collection work file_set relationship]).each do |type|
        if type.eql?('relationship')
          ScheduleRelationshipsJob.set(wait: 5.minutes).perform_later(importer_id: importerexporter.id)
          next
        end
        send(type.pluralize).each do |current_record|
          next unless record_has_source_identifier(current_record, index)
          break if limit_reached?(limit, index)

          seen[current_record[source_identifier]] = true
          create_entry_and_job(current_record, type)
          increment_counters(index, "#{type}": true)
          index += 1
        end
        importer.record_status
      end
      true
    rescue StandardError => e
      status_info(e)
    end

    def create_entry_and_job(current_record, type)
      new_entry = find_or_create_entry(send("#{type}_entry_class"),
                                       current_record[source_identifier],
                                       'Bulkrax::Importer',
                                       current_record.to_h)
      if current_record[:delete].present?
        "Bulkrax::Delete#{type.camelize}Job".constantize.send(perform_method, new_entry, current_run)
      else
        "Bulkrax::Import#{type.camelize}Job".constantize.send(perform_method, new_entry.id, current_run.id)
      end
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

    # rubocop:disable Metrics/AbcSize
    def current_record_ids
      @work_ids = []
      @collection_ids = []
      @file_set_ids = []

      case importerexporter.export_from
      when 'all'
        @work_ids = ActiveFedora::SolrService.query("has_model_ssim:(#{Hyrax.config.curation_concerns.join(' OR ')}) #{extra_filters}", method: :post, rows: 2_147_483_647).map(&:id)
        @collection_ids = ActiveFedora::SolrService.query("has_model_ssim:Collection #{extra_filters}", method: :post, rows: 2_147_483_647).map(&:id)
        @file_set_ids = ActiveFedora::SolrService.query("has_model_ssim:FileSet #{extra_filters}", method: :post, rows: 2_147_483_647).map(&:id)
      when 'collection'
        @work_ids = ActiveFedora::SolrService.query("member_of_collection_ids_ssim:#{importerexporter.export_source + extra_filters} AND has_model_ssim:(#{Hyrax.config.curation_concerns.join(' OR ')})", method: :post, rows: 2_000_000_000).map(&:id)
        # get the parent collection and child collections
        @collection_ids = ActiveFedora::SolrService.query("id:#{importerexporter.export_source} #{extra_filters}", method: :post, rows: 2_147_483_647).map(&:id)
        @collection_ids += ActiveFedora::SolrService.query("has_model_ssim:Collection AND member_of_collection_ids_ssim:#{importerexporter.export_source}", method: :post, rows: 2_147_483_647).map(&:id)
      when 'worktype'
        @work_ids = ActiveFedora::SolrService.query("has_model_ssim:#{importerexporter.export_source + extra_filters}", method: :post, rows: 2_000_000_000).map(&:id)
      when 'importer'
        set_ids_for_exporting_from_importer
      end

      find_child_file_sets(@work_ids) if importerexporter.export_from == 'collection'

      @work_ids + @collection_ids + @file_set_ids
    end
    # rubocop:enable Metrics/AbcSize

    # find the related file set ids so entries can be made for export
    def find_child_file_sets(work_ids)
      work_ids.each do |id|
        ActiveFedora::Base.find(id).file_set_ids.each { |fs_id| @file_set_ids << fs_id }
      end
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
        instance_variable_set(instance_var, ActiveFedora::SolrService.post(
          extra_filters.to_s,
          fq: [
            %(#{::Solrizer.solr_name(work_identifier)}:("#{complete_entry_identifiers.join('" OR "')}")),
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
    alias work_entry_class entry_class

    def collection_entry_class
      CsvCollectionEntry
    end

    def file_set_entry_class
      CsvFileSetEntry
    end

    # TODO: figure out why using the version of this method that's in the bagit parser
    # breaks specs for the "if importer?" line
    def total
      @total = importer.parser_fields['total'] || 0 if importer?
      @total = limit || current_record_ids.count if exporter?

      return @total || 0
    rescue StandardError
      @total = 0
    end

    def records_split_count
      1000
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
      require 'open-uri'
      folder_count = 0
      sorted_entries = sort_entries(importerexporter.entries.uniq(&:identifier))

      sorted_entries[0..limit || total].in_groups_of(records_split_count, false) do |group|
        folder_count += 1

        CSV.open(setup_export_file(folder_count), "w", headers: export_headers, write_headers: true) do |csv|
          group.each do |entry|
            csv << entry.parsed_metadata
            next if importerexporter.metadata_only? || entry.type == 'Bulkrax::CsvCollectionEntry'

            store_files(entry.identifier, folder_count.to_s)
          end
        end
      end
    end

    def store_files(identifier, folder_count)
      record = ActiveFedora::Base.find(identifier)
      return unless record

      file_sets = record.file_set? ? Array.wrap(record) : record.file_sets
      file_sets << record.thumbnail if exporter.include_thumbnails && record.thumbnail.present? && record.work?
      file_sets.each do |fs|
        path = File.join(exporter_export_path, folder_count, 'files')
        FileUtils.mkdir_p(path) unless File.exist? path
        file = filename(fs)
        io = open(fs.original_file.uri)
        next if file.blank?

        File.open(File.join(path, file), 'wb') do |f|
          f.write(io.read)
          f.close
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

    def sort_entries(entries)
      # always export models in the same order: work, collection, file set
      entries.sort_by do |entry|
        case entry.type
        when 'Bulkrax::CsvEntry'
          '0'
        when 'Bulkrax::CsvCollectionEntry'
          '1'
        when 'Bulkrax::CsvFileSetEntry'
          '2'
        end
      end
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
    def setup_export_file(folder_count)
      path = File.join(importerexporter.exporter_export_path, folder_count.to_s)
      FileUtils.mkdir_p(path) unless File.exist?(path)

      File.join(path, "export_#{importerexporter.export_source}_from_#{importerexporter.export_from}_#{folder_count}.csv")
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
    def path_to_files(**args)
      filename = args.fetch(:filename, '')

      @path_to_files ||= File.join(
        zip? ? importer_unzip_path : File.dirname(import_file_path), 'files', filename
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
