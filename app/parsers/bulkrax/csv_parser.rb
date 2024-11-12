# frozen_string_literal: true

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

    # rubocop:disable Metrics/AbcSize
    def build_records
      @collections = []
      @works = []
      @file_sets = []

      if model_field_mappings.map { |mfm| mfm.to_sym.in?(records.first.keys) }.any?
        records.map do |r|
          model_field_mappings.map(&:to_sym).each do |model_mapping|
            next unless r.key?(model_mapping)

            model = r[model_mapping].nil? ? "" : r[model_mapping].strip
            # TODO: Eventually this should be refactored to us Hyrax.config.collection_model
            #       We aren't right now because so many Bulkrax users are in between Fedora and Valkyrie
            if model.casecmp('collection').zero? || model.casecmp('collectionresource').zero?
              @collections << r
            elsif model.casecmp('fileset').zero?
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
    # rubocop:enabled Metrics/AbcSize

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

    def required_elements?(record)
      missing_elements(record).blank?
    end

    def missing_elements(record)
      keys_from_record = keys_without_numbers(record.reject { |_, v| v.blank? }.keys.compact.uniq.map(&:to_s))
      keys = []
      # Because we're persisting the mapping in the database, these are likely string keys.
      # However, there's no guarantee.  So, we need to ensure that by running stringify.
      importerexporter.mapping.stringify_keys.map do |k, v|
        Array.wrap(v['from']).each do |vf|
          keys << k if keys_from_record.include?(vf)
        end
      end
      required_elements.map(&:to_s) - keys.uniq.map(&:to_s)
    end

    def valid_import?
      compressed_record = records.flat_map(&:to_a).partition { |_, v| !v }.flatten(1).to_h
      error_alert = "Missing at least one required element, missing element(s) are: #{missing_elements(compressed_record).join(', ')}"
      raise StandardError, error_alert unless required_elements?(compressed_record)

      file_paths.is_a?(Array)
    rescue StandardError => e
      set_status_info(e)
      false
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

    def current_records_for_export
      @current_records_for_export ||= Bulkrax::ParserExportRecordSet.for(
        parser: self,
        export_from: importerexporter.export_from
      )
    end

    def create_new_entries
      # NOTE: The each method enforces the limit, as it can best optimize the underlying queries.
      current_records_for_export.each do |id, entry_class|
        new_entry = find_or_create_entry(entry_class, id, 'Bulkrax::Exporter')
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

    def valid_entry_types
      [collection_entry_class.to_s, file_set_entry_class.to_s, entry_class.to_s]
    end

    # TODO: figure out why using the version of this method that's in the bagit parser
    # breaks specs for the "if importer?" line
    def total
      @total =
        if importer?
          importer.parser_fields['total'] || 0
        elsif exporter?
          limit.to_i.zero? ? current_records_for_export.count : limit.to_i
        else
          0
        end

      return @total
    rescue StandardError
      @total = 0
    end

    def records_split_count
      1000
    end

    # @todo - investigate getting directory structure
    # @todo - investigate using perform_later, and having the importer check for
    #   DownloadCloudFileJob before it starts
    def retrieve_cloud_files(files, importer)
      files_path = File.join(path_for_import, 'files')
      FileUtils.mkdir_p(files_path) unless File.exist?(files_path)
      target_files = []
      files.each_pair do |_key, file|
        # fixes bug where auth headers do not get attached properly
        if file['auth_header'].present?
          file['headers'] ||= {}
          file['headers'].merge!(file['auth_header'])
        end
        # this only works for uniquely named files
        target_file = File.join(files_path, file['file_name'].tr(' ', '_'))
        target_files << target_file
        # Now because we want the files in place before the importer runs
        # Problematic for a large upload
        Bulkrax::DownloadCloudFileJob.perform_later(file, target_file)
      end
      importer[:parser_fields]['original_file_paths'] = target_files
      return nil
    end

    # export methods

    def write_files
      require 'open-uri'
      folder_count = 0
      # TODO: This is not performant as well; unclear how to address, but lower priority as of
      #       <2023-02-21 Tue>.
      sorted_entries = sort_entries(importerexporter.entries.uniq(&:identifier))
                       .select { |e| valid_entry_types.include?(e.type) }

      group_size = limit.to_i.zero? ? total : limit.to_i
      sorted_entries[0..group_size].in_groups_of(records_split_count, false) do |group|
        folder_count += 1

        CSV.open(setup_export_file(folder_count), "w", headers: export_headers, write_headers: true) do |csv|
          group.each do |entry|
            csv << entry.parsed_metadata
            # TODO: This is precarious when we have descendents of Bulkrax::CsvCollectionEntry
            next if importerexporter.metadata_only? || entry.type == 'Bulkrax::CsvCollectionEntry'

            store_files(entry.identifier, folder_count.to_s)
          end
        end
      end
    end

    def store_files(identifier, folder_count)
      record = Bulkrax.object_factory.find(identifier)
      return unless record

      file_sets = record.file_set? ? Array.wrap(record) : record.file_sets
      file_sets << record.thumbnail if exporter.include_thumbnails && record.thumbnail.present? && record.work?
      file_sets.each do |fs|
        path = File.join(exporter_export_path, folder_count, 'files')
        FileUtils.mkdir_p(path) unless File.exist? path
        file = filename(fs)
        next if file.blank? || fs.original_file.blank?

        io = open(fs.original_file.uri)
        File.open(File.join(path, file), 'wb') do |f|
          f.write(io.read)
          f.close
        end
      end
    rescue Ldp::Gone
      return
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
      @object_names.uniq!&.delete(nil)

      @object_names
    end

    def sort_entries(entries)
      # always export models in the same order: work, collection, file set
      #
      # TODO: This is a problem in that only these classes are compared.  Instead
      #       We should add a comparison operator to the classes.
      entries.sort_by do |entry|
        case entry.type
        when 'Bulkrax::CsvCollectionEntry'
          '1'
        when 'Bulkrax::CsvFileSetEntry'
          '2'
        else
          '0'
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

        r[file_mapping].split(multi_value_element_split_on).map do |f|
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

      return @path_to_files if @path_to_files.present? && filename.blank?
      @path_to_files = File.join(
          zip? ? importer_unzip_path : File.dirname(import_file_path), 'files', filename
        )
    end

    private

    def unique_collection_identifier(collection_hash)
      entry_uid = collection_hash[source_identifier]
      entry_uid ||= if Bulkrax.fill_in_blank_source_identifiers.present?
                      Bulkrax.fill_in_blank_source_identifiers.call(self, records.find_index(collection_hash))
                    else
                      collection_hash[:title].split(multi_value_element_split_on).first
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
