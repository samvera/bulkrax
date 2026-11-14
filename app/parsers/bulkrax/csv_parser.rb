# frozen_string_literal: true

module Bulkrax
  class CsvParser < ApplicationParser # rubocop:disable Metrics/ClassLength
    include ErroredEntries
    include ExportBehavior
    include CsvParser::CsvTemplateGeneration
    include CsvParser::CsvValidation
    attr_writer :collections, :file_sets, :works
    attr_accessor :validation_mode

    def self.export_supported?
      true
    end

    # @return [Regexp] the pattern String#split should use on a `file` cell.
    #   Honours the `file` mapping's `split:` when set, otherwise falls back
    #   to {Bulkrax.multi_value_element_split_on}.
    def self.file_split_pattern
      file_mapping = Bulkrax.field_mappings.dig(to_s, 'file') ||
                     Bulkrax.field_mappings.dig(to_s, :file) || {}
      split_value  = file_mapping['split'] || file_mapping[:split]
      Bulkrax::SplitPatternCoercion.coerce(split_value) || Bulkrax.multi_value_element_split_on
    end

    def create_objects(types_array = nil)
      record_deleted_identifiers(types_array)
      super
    rescue StandardError => e
      set_status_info(e)
    end

    # Each row's import job skips a relationship to a row this import deletes
    # (ImportBehavior#parent_jobs), even one whose own job has not run yet, so
    # the identifiers are saved before any job is queued.
    def record_deleted_identifiers(types_array = nil)
      types = (types_array || %w[collection work file_set]) - ['relationship']
      return if types.empty?

      deleted = queued_records(types).select { |record| record_deleted?(record) }
      mapping = deleted.empty? ? {} : importerexporter.mapping || {}
      identifiers = deleted.flat_map { |record| [record[source_identifier], Bulkrax::FieldResolver.row_id(record.to_h.transform_keys(&:to_s), mapping)&.last] }
                           .map { |value| value.to_s.strip }.reject(&:empty?)
      fields = importerexporter.parser_fields
      # Each record type may be submitted separately; keep the run's earlier ones.
      earlier = fields['deleted_identifiers_run_id'] == current_run.id ? Array(fields['deleted_identifiers']) : []
      fields['deleted_identifiers'] = (earlier + identifiers).uniq
      fields['deleted_identifiers_run_id'] = current_run.id
      importerexporter.save
    end

    # An Existing Entries run submits entries as imports and deletes nothing.
    def rebuild_entries(types_array = nil)
      importerexporter.parser_fields['deleted_identifiers'] = []
      importerexporter.save
      super
    end

    # The rows #create_objects queues: those with a source identifier, or one
    # Bulkrax fills in, up to the import limit.
    def queued_records(types)
      fills_in = Bulkrax.fill_in_blank_source_identifiers.present?
      queued = types.flat_map { |type| send(type.pluralize) }.select { |record| record[source_identifier].present? || fills_in }
      limit.nil? || limit.zero? ? queued : queued.first(limit)
    end

    def records(_opts = {})
      return @records if @records.present?

      csv_data = entry_class.read_data(file_for_import)
      unless validation_mode
        importer.parser_fields['total'] = csv_data.count
        importer.save
      end

      @records = csv_data.map { |record_data| entry_class.data_for_entry(record_data, nil, self) }
      @records
    end

    def build_records
      @collections = []
      @works = []
      @file_sets = []

      if model_field_mappings.map { |mfm| mfm.to_sym.in?(records.first.keys) }.any?
        records.map do |r|
          model_field_mappings.map(&:to_sym).each do |model_mapping|
            next unless r.key?(model_mapping)

            model = r[model_mapping].nil? ? "" : r[model_mapping].strip
            if Bulkrax.collection_model_name?(model)
              @collections << r
            elsif Bulkrax.file_model_name?(model)
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
    # Every row has every header, so the first row's keys are the whole
    # sheet's; reading one row keeps each import job from parsing the file.
    def import_fields
      @import_fields ||= first_record_keys || records.inject(:merge).keys.compact.uniq
    end

    def required_elements?(record)
      missing_elements(record).blank?
    end

    def missing_elements(record)
      keys_from_record = keys_without_numbers(record.reject { |_, v| v.blank? }.keys.compact.uniq.map(&:to_s))
      mapping_values = importerexporter.mapping.stringify_keys
      keys = keys_from_record.flat_map { |header| Bulkrax::FieldResolver.fields_for_header(mapping_values, header) }
      required_elements.map(&:to_s) - keys.uniq.map(&:to_s)
    end

    def valid_import?
      # A row that only deletes needs no metadata: its record is never built.
      kept = records.reject { |record| record_deleted?(record) }
      if kept.any?
        compressed_record = kept.flat_map(&:to_a).partition { |_, v| !v }.flatten(1).to_h
        error_alert = "Missing at least one required element, missing element(s) are: #{missing_elements(compressed_record).join(', ')}"
        raise StandardError, error_alert unless required_elements?(compressed_record)
      end

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
      plan = plan_cloud_files(files)
      dispatch_cloud_files!(plan, importer)
      importer[:parser_fields]['original_file_paths'] = plan.map { |_file, _relative_filename, target_file| target_file }
      return nil
    end

    # Validates and resolves the whole batch, without enqueueing anything
    # yet. Otherwise an earlier, valid file's job would already be running
    # by the time a later file in the same batch is found to be unsafe.
    # Split out from {#retrieve_cloud_files} so a caller (the importers
    # controller) can persist the resolved paths before dispatching.
    #
    # @return [Array<Array(Hash, String, String)>] one entry per file: the
    #   file spec, its relative destination filename, and the resolved
    #   absolute target path
    def plan_cloud_files(files)
      files_path = File.join(path_for_import, 'files')
      FileUtils.mkdir_p(files_path) unless File.exist?(files_path)

      files.values.map { |file| plan_cloud_file(file) }
    end

    # Enqueues a download job for each entry of an already-validated plan
    # (see {#plan_cloud_files}).
    def dispatch_cloud_files!(plan, importer)
      plan.each { |file, relative_filename, _target_file| Bulkrax::DownloadCloudFileJob.perform_later(file, importer_id: importer.id, relative_filename: relative_filename) }
    end

    # Validates one cloud-file spec and resolves its destination, without
    # enqueueing anything yet.
    #
    # @return [Array(Hash, String, String)] the file spec, its relative
    #   destination filename, and the resolved absolute target path
    def plan_cloud_file(file)
      # fixes bug where auth headers do not get attached properly
      if file['auth_header'].present?
        file['headers'] ||= {}
        file['headers'].merge!(file['auth_header'])
      end

      # Checked on the raw file_name, before it's joined under 'files/':
      # that join would otherwise neutralize a leading `/` (File.join
      # doesn't treat it as absolute once it's not the first argument).
      Bulkrax::CloudSourceValidator.preflight!(file)

      # this only works for uniquely named files
      relative_filename = File.join('files', file['file_name'].tr(' ', '_'))
      target_file = Bulkrax::SafePath.confine!(path_for_import, relative_filename, require_file: true)
      [file, relative_filename, target_file]
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

      file_sets = record.file_set? ? [record] : Array(Bulkrax.object_factory.file_sets_for(resource: record))

      if importerexporter.include_thumbnails?
        thumbnail = Bulkrax.object_factory.thumbnail_for(resource: record)
        file_sets << thumbnail if thumbnail.present?
      end

      file_sets.each do |fs|
        path = File.join(exporter_export_path, folder_count, 'files')
        FileUtils.mkdir_p(path) unless File.exist? path

        original_file = Bulkrax.object_factory.original_file(fileset: fs)
        next if original_file.blank?
        file = filename(fs)

        io = original_file.respond_to?(:uri) ? open(original_file.uri) : original_file.file.io

        File.open(File.join(path, file), 'wb') do |f|
          f.write(io.read)
          f.close
        end
      end
    rescue Ldp::Gone
      return
    rescue StandardError => e
      raise StandardError, "Unable to retrieve files for identifier #{identifier} - #{e.message}"
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

      # Compute once — these don't vary per record.
      file_headers  = Bulkrax::FieldResolver.headers_for_field(Bulkrax.field_mappings[self.class.to_s], 'file')
      split_pattern = self.class.file_split_pattern
      files_dir     = path_to_files

      @file_paths ||= records.map do |r|
        raw_values = r.select { |key, _| Bulkrax::FieldResolver.header_for_any?(key, file_headers) }.values.reject(&:blank?)
        next if raw_values.empty? || record_deleted?(r)
        raise StandardError, "Record references local files but no files directory could be resolved from the import path" if files_dir.nil?

        raw_values.flat_map { |v| v.split(split_pattern) }.map(&:strip).reject(&:empty?).map { |f| existing_file_path(files_dir, f) }
      end.flatten.compact.uniq
    end

    # Retrieve the path where we expect to find the files for this import.
    # After {ImporterJob#unzip_imported_file} runs (zip cases), attachments
    # live under `{importer_unzip_path}/files/`. For a server-path-style
    # import (the user specified a CSV file path with a sibling `files/`
    # directory on disk), resolve relative to the CSV's directory instead.
    #
    # When called with `filename:`, returns the full path to that file if
    # it exists on disk, or `nil` otherwise — callers like
    # `Bulkrax::FileSetEntryBehavior#add_path_to_file` rely on the nil
    # sentinel to fall back to the raw filename in their error messages.
    #
    # When called with no filename, returns the `files/` directory itself
    # (only when that directory exists on disk — else `nil` so callers can
    # raise a clear "no files directory" error).
    def path_to_files(**args)
      filename = args.fetch(:filename, '')
      base_dir = files_dir
      return base_dir if filename.blank? && Dir.exist?(base_dir)
      return nil if filename.blank?

      self.class.file_reference_candidates(filename)
          .map { |candidate| File.join(base_dir, candidate) }
          .find { |candidate| File.file?(candidate) }
    end

    # The names a file reference may have under `files/` after extraction,
    # ignoring empty and `.` segments as extraction does: as written, or with
    # spaces underscored in the top-level name, the only one
    # #remove_spaces_from_filenames renames. A reference ending in a slash
    # names a folder, not a file, so it has none.
    def self.file_reference_candidates(reference)
      return [] if reference.end_with?('/', '/.')

      cleaned = reference.split('/').reject { |part| part.empty? || part == '.' }.join('/')
      return [] if cleaned.empty?

      top, rest = cleaned.split('/', 2)
      [cleaned, [top.tr(' ', '_'), rest].compact.join('/')].uniq
    end

    # Extracts a zip that contains a primary CSV. The primary CSV lands at
    # the root of {#importer_unzip_path}; every other entry lands under
    # {#importer_unzip_path}/files/, preserving its path relative to the
    # primary CSV's directory.
    #
    # Primary-CSV selection matches the guided-import validator's rule
    # (see {Bulkrax::ImporterFileHandler#locate_csv_entry_in_zip}): the CSV
    # entry at the shallowest directory level. Visible errors are raised on
    # zero CSVs or multiple CSVs at the shallowest level.
    #
    # @param file_to_unzip [String] absolute path to a .zip
    # @raise [Bulkrax::UnzipError] on no CSV or ambiguous CSVs
    def unzip_with_primary_csv(file_to_unzip)
      dest_dir = importer_unzip_path(mkdir: true)
      Zip::File.open(file_to_unzip) do |zip_file|
        entries = real_zip_entries(zip_file)
        plan = Bulkrax::ZipPlacementPlanner.plan(entries, mode: :primary_csv)
        plan.placements.each { |entry, dest| extract_to(zip_file, entry, dest_dir, dest) }
      end
    end

    # Extracts a zip that accompanies a separately-uploaded CSV. Every
    # entry lands under {#importer_unzip_path}/files/ — including any
    # CSVs inside the zip, which are treated as attachments since the
    # primary CSV was uploaded outside the zip. Strips a single top-level
    # wrapper directory if present, so users can zip either the contents
    # or the enclosing folder.
    #
    # @param file_to_unzip [String] absolute path to a .zip
    def unzip_attachments_only(file_to_unzip)
      dest_dir = importer_unzip_path(mkdir: true)
      Zip::File.open(file_to_unzip) do |zip_file|
        entries = real_zip_entries(zip_file)
        plan = Bulkrax::ZipPlacementPlanner.plan(entries, mode: :attachments_only)
        plan.placements.each { |entry, dest| extract_to(zip_file, entry, dest_dir, dest) }
      end
    end

    # File names referenced in CSVs have spaces replaced with underscores.
    # @see #file_paths
    def remove_spaces_from_filenames
      files = Dir.glob(File.join(importer_unzip_path, 'files', '*'))
      files_with_spaces = files.select { |f| f.split('/').last.include?(' ') }
      return if files_with_spaces.blank?

      files_with_spaces.map! { |path| Pathname.new(path) }
      files_with_spaces.each do |path|
        filename_without_spaces = path.basename.to_s.tr(' ', '_')
        path.rename(File.join(path.dirname, filename_without_spaces))
      end
    end

    # Returns zip entries filtered down to real files (no directories, no
    # macOS junk). Raises {Bulkrax::UnzipError} if any entry's name would
    # escape the destination directory (Zip Slip).
    def self.real_zip_entries(zip_file)
      entries = zip_file.entries.select { |e| e.file? && !macos_junk_entry?(e.name) }
      entries.each { |e| CsvParser.reject_unsafe_entry!(e.name) }
      entries
    end

    private

    def file_for_import
      only_updates ? parser_fields['partial_import_file_path'] : import_file_path
    end

    def first_record_keys
      return if @records.present?

      row = entry_class.read_first_row(file_for_import)
      entry_class.data_for_entry(row, nil, self).keys.compact.uniq if row
    end

    def existing_file_path(files_dir, reference)
      file = self.class.file_reference_candidates(reference)
                 .map { |candidate| File.join(files_dir, candidate) }
                 .find { |candidate| File.file?(candidate) }
      raise "File #{File.join(files_dir, reference)} does not exist" if file.nil?

      file
    end

    # Memoized base directory under which import attachments live. Kept
    # separate from `#path_to_files`' per-filename return value to avoid
    # cross-contamination between directory lookups and file lookups.
    def files_dir
      @files_dir ||= begin
        has_attachments_zip = parser_fields['attachments_zip_path'].present? && zip_file?(parser_fields['attachments_zip_path'])
        base = zip? || has_attachments_zip ? importer_unzip_path : File.dirname(import_file_path)
        File.join(base, 'files')
      end
    end

    def real_zip_entries(zip_file)
      self.class.real_zip_entries(zip_file)
    end

    # Extracts a zip entry to `dest_dir/relative_dest`. Creates intermediate
    # directories and honors the rubyzip 2/3 extract-method signature.
    # The destination path is validated by {#safe_extract_path} — an unsafe
    # `relative_dest` raises {Bulkrax::UnzipError} before any write.
    def extract_to(zip_file, entry, dest_dir, relative_dest)
      dest_path = safe_extract_path(dest_dir, relative_dest)
      FileUtils.mkdir_p(File.dirname(dest_path))
      return if File.exist?(dest_path)
      extract_zip_entry(zip_file, entry, dest_dir, relative_dest, dest_path)
    end

    def unique_collection_identifier(collection_hash)
      entry_uid = collection_hash[source_identifier]
      entry_uid ||= if Bulkrax.fill_in_blank_source_identifiers.present?
                      Bulkrax.fill_in_blank_source_identifiers.call(self, records.find_index(collection_hash))
                    else
                      collection_hash[:title].split(Bulkrax.multi_value_element_split_on).first
                    end

      entry_uid
    end

    # Override to return the first CSV in the path, if a zip file is supplied
    # We expect a single CSV at the top level of the zip in the CSVParser
    # but we are willing to go look for it if need be
    # When the user uploaded a zip containing a CSV, the job extracts the
    # primary CSV to the root of `importer_unzip_path` (see
    # {#unzip_with_primary_csv}). Any non-primary CSVs live under `files/`
    # and are treated as attachments, so a shallow glob suffices.
    def real_import_file_path
      return Dir["#{importer_unzip_path}/*.csv"].first if file? && zip?
      parser_fields['import_file_path']
    end
  end
end
