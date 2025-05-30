# frozen_string_literal: true

module Bulkrax
  # An abstract class that establishes the API for Bulkrax's import and export parsing.
  #
  # @abstract Subclass the Bulkrax::ApplicationParser to create a parser that handles a specific format (e.g. CSV, Bagit, XML, etc).
  class ApplicationParser # rubocop:disable Metrics/ClassLength
    attr_accessor :importerexporter, :headers
    alias importer importerexporter
    alias exporter importerexporter
    delegate :only_updates, :limit, :current_run, :errors, :mapping,
             :seen, :increment_counters, :parser_fields, :user, :keys_without_numbers,
             :key_without_numbers, :status, :set_status_info, :status_info, :status_at,
             :exporter_export_path, :exporter_export_zip_path, :importer_unzip_path, :validate_only,
             :zip?, :file?, :remove_and_rerun,
             to: :importerexporter

    # @todo Convert to `class_attribute :parser_fiels, default: {}`
    def self.parser_fields
      {}
    end

    # @return [TrueClass,FalseClass] this parser does or does not support exports.
    #
    # @todo Convert to `class_attribute :export_supported, default: false, instance_predicate: true` and `self << class; alias export_supported? export_supported; end`
    def self.export_supported?
      false
    end

    # @return [TrueClass,FalseClass] this parser does or does not support imports.
    #
    # @todo Convert to `class_attribute :import_supported, default: false, instance_predicate: true` and `self << class; alias import_supported? import_supported; end`
    def self.import_supported?
      true
    end

    def initialize(importerexporter)
      @importerexporter = importerexporter
      @headers = []
    end

    # @api public
    # @abstract Subclass and override {#entry_class} to implement behavior for the parser.
    def entry_class
      raise NotImplementedError, 'must be defined'
    end

    def work_entry_class
      entry_class
    end

    # @api public
    # @abstract Subclass and override {#collection_entry_class} to implement behavior for the parser.
    def collection_entry_class
      raise NotImplementedError, 'must be defined'
    end

    # @api public
    # @abstract Subclass and override {#file_set_entry_class} to implement behavior for the parser.
    def file_set_entry_class
      raise NotImplementedError, 'must be defined'
    end

    # @api public
    # @abstract Subclass and override {#records} to implement behavior for the parser.
    def records(_opts = {})
      raise NotImplementedError, 'must be defined'
    end

    # @return [Symbol] the name of the identifying property in the source system from which we're
    # importing (e.g. is *not* this application that mounts *this* Bulkrax engine).
    #
    # @see #work_identifier
    # @see https://github.com/samvera-labs/bulkrax/wiki/CSV-Importer#source-identifier Bulkrax Wiki regarding source identifier
    def source_identifier
      @source_identifier ||= get_field_mapping_hash_for('source_identifier')&.values&.first&.[]('from')&.first&.to_sym || :source_identifier
    end

    # @return [Symbol] the name of the identifying property for the system which we're importing
    #         into (e.g. the application that mounts *this* Bulkrax engine)
    # @see #source_identifier
    def work_identifier
      @work_identifier ||= get_field_mapping_hash_for('source_identifier')&.keys&.first&.to_sym || :source
    end

    # @return [Symbol] the solr property of the source_identifier. Used for searching.
    #         defaults to work_identifier value + "_sim"
    # @see #work_identifier
    def work_identifier_search_field
      @work_identifier_search_field ||= Array.wrap(get_field_mapping_hash_for('source_identifier')&.values&.first&.[]('search_field'))&.first&.to_s || "#{work_identifier}_sim"
    end

    # @return [String]
    def generated_metadata_mapping
      @generated_metadata_mapping ||= 'generated'
    end

    # @return [String, NilClass]
    # @see #related_parents_raw_mapping
    def related_parents_raw_mapping
      @related_parents_raw_mapping ||= get_field_mapping_hash_for('related_parents_field_mapping')&.values&.first&.[]('from')&.first
    end

    # @return [String]
    # @see #related_parents_field_mapping
    def related_parents_parsed_mapping
      @related_parents_parsed_mapping ||= get_field_mapping_hash_for('related_parents_field_mapping')&.keys&.first || 'parents'
    end

    # @return [String, NilClass]
    # @see #related_children_parsed_mapping
    def related_children_raw_mapping
      @related_children_raw_mapping ||= get_field_mapping_hash_for('related_children_field_mapping')&.values&.first&.[]('from')&.first
    end

    # @return [String]
    # @see #related_children_raw_mapping
    def related_children_parsed_mapping
      @related_children_parsed_mapping ||= get_field_mapping_hash_for('related_children_field_mapping')&.keys&.first || 'children'
    end

    # @api private
    def get_field_mapping_hash_for(key)
      return instance_variable_get("@#{key}_hash") if instance_variable_get("@#{key}_hash").present?

      mapping = importerexporter.field_mapping.is_a?(Hash) ? importerexporter.field_mapping : {}
      instance_variable_set(
        "@#{key}_hash",
        mapping&.with_indifferent_access&.select { |_, h| h.key?(key) }
      )
      raise StandardError, "more than one #{key} declared: #{instance_variable_get("@#{key}_hash").keys.join(', ')}" if instance_variable_get("@#{key}_hash").length > 1

      instance_variable_get("@#{key}_hash")
    end

    # @return [Array<String>]
    def model_field_mappings
      model_mappings = Bulkrax.field_mappings[self.class.to_s]&.dig('model', :from) || []
      model_mappings |= ['model']

      model_mappings
    end

    # @return [String]
    def perform_method
      if self.validate_only
        'perform_now'
      else
        'perform_later'
      end
    end

    # The visibility of the record.  Acceptable values are: "open", "embargo", "lease", "authenticated", "restricted".  The default is "open"
    #
    # @return [String]
    # @see https://github.com/samvera/hydra-head/blob/main/hydra-access-controls/app/models/concerns/hydra/access_controls/access_right.rb Hydra::AccessControls::AccessRight for details on the range of values.
    # @see https://github.com/samvera/hyrax/blob/bd2bcffc33e183904be2c175367648815f25bc2b/app/services/hyrax/visibility_intention.rb Hyrax::VisibilityIntention for how we process the visibility.
    def visibility
      @visibility ||= self.parser_fields['visibility'] || 'open'
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

    # @api public
    #
    # @param types [Array<Symbol>] the types of objects that we'll create.
    #
    # @see Bulkrax::Importer::DEFAULT_OBJECT_TYPES
    # @see #create_collections
    # @see #create_works
    # @see #create_file_sets
    # @see #create_relationships
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
      set_status_info(e)
    end

    def rebuild_entries(types_array = nil)
      index = 0
      (types_array || %w[collection work file_set relationship]).each do |type|
        # works are not gurneteed to have Work in the type

        importer.entries.where(rebuild_entry_query(type, parser_fields['entry_statuses'])).find_each do |e|
          seen[e.identifier] = true
          e.status_info('Pending', importer.current_run)
          if remove_and_rerun
            delay = calculate_type_delay(type)
            "Bulkrax::DeleteAndImport#{type.camelize}Job".constantize.set(wait: delay).send(perform_method, e, current_run)
          else
            "Bulkrax::Import#{type.camelize}Job".constantize.send(perform_method, e.id, current_run.id)
          end
          increment_counters(index)
          index += 1
        end
      end
    end

    def rebuild_entry_query(type, statuses)
      type_col = Bulkrax::Entry.arel_table['type']
      status_col = Bulkrax::Entry.arel_table['status_message']

      query = (type == 'work' ? type_col.does_not_match_all(%w[collection file_set]) : type_col.matches(type.camelize))
      query.and(status_col.in(statuses))
    end

    def calculate_type_delay(type)
      return 2.minutes if type == 'file_set'
      return 1.minute if type == 'work'
      return 0
    end

    def record_raw_metadata(record)
      record.to_h
    end

    def record_deleted?(record)
      return false unless record.key?(:delete)
      ActiveModel::Type::Boolean.new.cast(record[:delete])
    end

    def record_remove_and_rerun?(record)
      return false unless record.key?(:remove_and_rerun)
      ActiveModel::Type::Boolean.new.cast(record[:remove_and_rerun])
    end

    def create_entry_and_job(current_record, type, identifier = nil)
      identifier ||= current_record[source_identifier]
      new_entry = find_or_create_entry(send("#{type}_entry_class"),
                                       identifier,
                                       'Bulkrax::Importer',
                                       record_raw_metadata(current_record))
      new_entry.status_info('Pending', importer.current_run)
      if record_deleted?(current_record)
        "Bulkrax::Delete#{type.camelize}Job".constantize.send(perform_method, new_entry, current_run)
      elsif record_remove_and_rerun?(current_record) || remove_and_rerun
        delay = calculate_type_delay(type)
        "Bulkrax::DeleteAndImport#{type.camelize}Job".constantize.set(wait: delay).send(perform_method, new_entry, current_run)
      else
        "Bulkrax::Import#{type.camelize}Job".constantize.send(perform_method, new_entry.id, current_run.id)
      end
    end

    # Optional, define if using browse everything for file upload
    def retrieve_cloud_files(_files, _importer); end

    # @param file [#path, #original_filename] the file object that with the relevant data for the
    #        import.
    def write_import_file(file)
      path = File.join(path_for_import, file.original_filename)
      FileUtils.mv(
        file.path,
        path
      )
      path
    end

    # Base path for imported and exported files
    # @param [String]
    # @return [String] the base path for files that this parser will "parse"
    def base_path(type = 'import')
      # account for multiple versions of hyku
      is_multitenant = ENV['HYKU_MULTITENANT'] == 'true' || ENV['SETTINGS__MULTITENANCY__ENABLED'] == 'true'
      is_multitenant ? File.join(Bulkrax.send("#{type}_path"), ::Site.instance.account.name) : Bulkrax.send("#{type}_path")
    end

    # Path where we'll store the import metadata and files
    #  this is used for uploaded and cloud files
    # @return [String]
    def path_for_import
      @path_for_import = File.join(base_path, importerexporter.path_string)
      FileUtils.mkdir_p(@path_for_import) unless File.exist?(@path_for_import)
      @path_for_import
    end

    # @abstract Subclass and override {#setup_export_file} to implement behavior for the parser.
    def setup_export_file
      raise NotImplementedError, 'must be defined' if exporter?
    end

    # @abstract Subclass and override {#write_files} to implement behavior for the parser.
    def write_files
      raise NotImplementedError, 'must be defined' if exporter?
    end

    # @return [TrueClass,FalseClass]
    def importer?
      importerexporter.is_a?(Bulkrax::Importer)
    end

    # @return [TrueClass,FalseClass]
    def exporter?
      importerexporter.is_a?(Bulkrax::Exporter)
    end

    # @param limit [Integer] limit set on the importerexporter
    # @param index [Integer] index of current iteration
    # @return [TrueClass,FalseClass]
    def limit_reached?(limit, index)
      return false if limit.nil? || limit.zero? # no limit
      index >= limit
    end

    # Override to add specific validations
    # @return [TrueClass,FalseClass]
    def valid_import?
      true
    end

    # @return [TrueClass,FalseClass]
    def record_has_source_identifier(record, index)
      if record[source_identifier].blank?
        if Bulkrax.fill_in_blank_source_identifiers.present?
          record[source_identifier] = Bulkrax.fill_in_blank_source_identifiers.call(self, index)
        else
          invalid_record("Missing #{source_identifier} for #{record.to_h}\n")
          false
        end
      else
        true
      end
    end

    # rubocop:disable Rails/SkipsModelValidations
    def invalid_record(message)
      current_run.invalid_records ||= ""
      current_run.invalid_records += message
      current_run.save
      ImporterRun.increment_counter(:failed_records, current_run.id)
      ImporterRun.decrement_counter(:enqueued_records, current_run.id) unless ImporterRun.find(current_run.id).enqueued_records <= 0 # rubocop:disable Style/IdenticalConditionalBranches
    end
    # rubocop:enable Rails/SkipsModelValidations

    # @return [Array<String>]
    def required_elements
      matched_elements = ((importerexporter.mapping.keys || []) & (Bulkrax.required_elements || []))
      unless matched_elements.count == Bulkrax.required_elements.count
        missing_elements = Bulkrax.required_elements - matched_elements
        error_alert = "Missing mapping for at least one required element, missing mappings are: #{missing_elements.join(', ')}"
        raise StandardError, error_alert
      end
      if Bulkrax.fill_in_blank_source_identifiers
        Bulkrax.required_elements
      else
        Bulkrax.required_elements + [source_identifier]
      end
    end

    def new_entry(entryclass, type)
      entryclass.new(
        importerexporter_id: importerexporter.id,
        importerexporter_type: type
      )
    end

    def find_or_create_entry(entryclass, identifier, type, raw_metadata = nil)
      # limit entry search to just this importer or exporter. Don't go moving them
      entry = importerexporter.entries.where(
        identifier: identifier
      ).first
      entry ||= entryclass.new(
        importerexporter_id: importerexporter.id,
        importerexporter_type: type,
        identifier: identifier
      )
      entry.raw_metadata = raw_metadata
      # Setting parsed_metadata specifically for the id so we can find the object via the
      # id in a delete.  This is likely to get clobbered in a regular import, which is fine.
      entry.parsed_metadata = { id: raw_metadata['id'] } if raw_metadata&.key?('id')
      entry.save!
      entry
    end

    # @todo - review this method - is it ever used?
    def record(identifier, _opts = {})
      return @record if @record

      @record = entry_class.new(self, identifier)
      @record.build
      return @record
    end

    def total
      0
    end

    def collections_total
      0
    end

    def file_sets_total
      0
    end

    def write
      write_files
      zip
    end

    def unzip(file_to_unzip)
      return untar(file_to_unzip) if file_to_unzip.end_with?('.tar.gz')

      Zip::File.open(file_to_unzip) do |zip_file|
        zip_file.each do |entry|
          entry_path = File.join(importer_unzip_path(mkdir: true), entry.name)
          FileUtils.mkdir_p(File.dirname(entry_path))
          zip_file.extract(entry, entry_path) unless File.exist?(entry_path)
        end
      end
    end

    def untar(file_to_untar)
      Dir.mkdir(importer_unzip_path(mkdir: true)) unless File.directory?(importer_unzip_path(mkdir: true))
      command = "tar -xzf #{Shellwords.escape(file_to_untar)} -C #{Shellwords.escape(importer_unzip_path)}"
      result = system(command)
      raise "Failed to extract #{file_to_untar}" unless result
    end

    # File names referenced in CSVs have spaces replaced with underscores
    # @see Bulkrax::CsvParser#file_paths
    def remove_spaces_from_filenames
      files = Dir.glob(File.join(importer_unzip_path, 'files', '*'))
      files_with_spaces = files.select { |f| f.split('/').last.match?(' ') }
      return if files_with_spaces.blank?

      files_with_spaces.map! { |path| Pathname.new(path) }
      files_with_spaces.each do |path|
        filename = path.basename
        filename_without_spaces = filename.to_s.tr(' ', '_')
        path.rename(File.join(path.dirname, filename_without_spaces))
      end
    end

    def zip
      FileUtils.mkdir_p(exporter_export_zip_path)

      Dir["#{exporter_export_path}/**"].each do |folder|
        zip_path = "#{exporter_export_zip_path.split('/').last}_#{folder.split('/').last}.zip"
        FileUtils.rm_rf("#{exporter_export_zip_path}/#{zip_path}")

        Zip::File.open(File.join("#{exporter_export_zip_path}/#{zip_path}"), create: true) do |zip_file|
          Dir["#{folder}/**/**"].each do |file|
            zip_file.add(file.sub("#{folder}/", ''), file)
          end
        end
      end
    end

    # Path for the import
    # @return [String]
    def import_file_path
      @import_file_path ||= real_import_file_path
    end

    private

    # @return [String]
    def real_import_file_path
      return importer_unzip_path if file? && zip?
      parser_fields['import_file_path']
    end
  end
end
