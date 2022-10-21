# frozen_string_literal: true
require 'zip'

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
      :key_without_numbers, :status, :status_info, :status_at,
      :exporter_export_path, :exporter_export_zip_path, :importer_unzip_path, :validate_only,
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

    # @api public
    # @abstract Subclass and override {#collection_entry_class} to implement behavior for the parser.
    def collection_entry_class
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
      @related_parents_parsed_mapping ||= (get_field_mapping_hash_for('related_parents_field_mapping')&.keys&.first || 'parents')
    end

    # @return [String, NilClass]
    # @see #related_children_parsed_mapping
    def related_children_raw_mapping
      @related_children_raw_mapping ||= get_field_mapping_hash_for('related_children_field_mapping')&.values&.first&.[]('from')&.first
    end

    # @return [String]
    # @see #related_children_raw_mapping
    def related_children_parsed_mapping
      @related_children_parsed_mapping ||= (get_field_mapping_hash_for('related_children_field_mapping')&.keys&.first || 'children')
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

    # The visibility of the record.  Acceptable values are: "open", "embaro", "lease", "authenticated", "restricted".  The default is "open"
    #
    # @return [String]
    # @see https://github.com/samvera/hydra-head/blob/main/hydra-access-controls/app/models/concerns/hydra/access_controls/access_right.rb Hydra::AccessControls::AccessRight for details on the range of values.
    # @see https://github.com/samvera/hyrax/blob/bd2bcffc33e183904be2c175367648815f25bc2b/app/services/hyrax/visibility_intention.rb Hyrax::VisibilityIntention for how we process the visibility.
    def visibility
      @visibility ||= self.parser_fields['visibility'] || 'open'
    end

    # @abstract Subclass and override {#create_collections} to implement behavior for the parser.
    def create_collections
      raise NotImplementedError, 'must be defined' if importer?
    end

    # @abstract Subclass and override {#create_works} to implement behavior for the parser.
    def create_works
      raise NotImplementedError, 'must be defined' if importer?
    end

    # @abstract Subclass and override {#create_file_sets} to implement behavior for the parser.
    def create_file_sets
      raise NotImplementedError, 'must be defined' if importer?
    end

    # @abstract Subclass and override {#create_relationships} to implement behavior for the parser.
    def create_relationships
      raise NotImplementedError, 'must be defined' if importer?
    end

    # Optional, define if using browse everything for file upload
    def retrieve_cloud_files(files); end

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
      ImporterRun.find(current_run.id).increment!(:failed_records)
      ImporterRun.find(current_run.id).decrement!(:enqueued_records) unless ImporterRun.find(current_run.id).enqueued_records <= 0 # rubocop:disable Style/IdenticalConditionalBranches
    end
    # rubocop:enable Rails/SkipsModelValidations

    # @return [Array<String>]
    def required_elements
      if Bulkrax.fill_in_blank_source_identifiers
        ['title']
      else
        ['title', source_identifier]
      end
    end

    def new_entry(entryclass, type)
      entryclass.new(
        importerexporter_id: importerexporter.id,
        importerexporter_type: type
      )
    end

    def find_or_create_entry(entryclass, identifier, type, raw_metadata = nil)
      entry = entryclass.where(
        importerexporter_id: importerexporter.id,
        importerexporter_type: type,
        identifier: identifier
      ).first_or_create!
      entry.raw_metadata = raw_metadata
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
      Zip::File.open(file_to_unzip) do |zip_file|
        zip_file.each do |entry|
          entry_path = File.join(importer_unzip_path, entry.name)
          FileUtils.mkdir_p(File.dirname(entry_path))
          zip_file.extract(entry, entry_path) unless File.exist?(entry_path)
        end
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

    # Is this a file?
    def file?
      parser_fields&.[]('import_file_path') && File.file?(parser_fields['import_file_path'])
    end

    # Is this a zip file?
    def zip?
      parser_fields&.[]('import_file_path') && MIME::Types.type_for(parser_fields['import_file_path']).include?('application/zip')
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
