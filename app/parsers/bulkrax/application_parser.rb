# frozen_string_literal: true

module Bulkrax
  class ApplicationParser # rubocop:disable Metrics/ClassLength
    attr_accessor :importerexporter, :headers
    alias importer importerexporter
    alias exporter importerexporter
    delegate :only_updates, :limit, :current_run, :errors, :mapping,
      :seen, :increment_counters, :parser_fields, :user, :keys_without_numbers,
      :key_without_numbers, :status, :status_info, :status_at,
      :exporter_export_path, :exporter_export_zip_path, :importer_unzip_path, :validate_only,
      to: :importerexporter

    def self.parser_fields
      {}
    end

    def self.export_supported?
      false
    end

    def self.import_supported?
      true
    end

    def initialize(importerexporter)
      @importerexporter = importerexporter
      @headers = []
    end

    # @api
    def entry_class
      raise StandardError, 'must be defined'
    end

    # @api
    def collection_entry_class
      raise StandardError, 'must be defined'
    end

    # @api
    def records(_opts = {})
      raise StandardError, 'must be defined'
    end

    def source_identifier
      @source_identifier ||= get_field_mapping_hash_for('source_identifier')&.values&.first&.[]('from')&.first&.to_sym || :source_identifier
    end

    def work_identifier
      @work_identifier ||= get_field_mapping_hash_for('source_identifier')&.keys&.first&.to_sym || :source
    end

    def related_parents_raw_mapping
      @related_parents_raw_mapping ||= get_field_mapping_hash_for('related_parents_field_mapping')&.values&.first&.[]('from')&.first
    end

    def related_parents_parsed_mapping
      @related_parents_parsed_mapping ||= get_field_mapping_hash_for('related_parents_field_mapping')&.keys&.first
    end

    def related_children_raw_mapping
      @related_children_raw_mapping ||= get_field_mapping_hash_for('related_children_field_mapping')&.values&.first&.[]('from')&.first
    end

    def related_children_parsed_mapping
      @related_children_parsed_mapping ||= get_field_mapping_hash_for('related_children_field_mapping')&.keys&.first
    end

    def get_field_mapping_hash_for(key)
      return instance_variable_get("@#{key}_hash") if instance_variable_get("@#{key}_hash").present?

      instance_variable_set(
        "@#{key}_hash",
        importerexporter.mapping.with_indifferent_access.select { |_, h| h.key?(key) }
      )
      raise StandardError, "more than one #{key} declared: #{instance_variable_get("@#{key}_hash").keys.join(', ')}" if instance_variable_get("@#{key}_hash").length > 1

      instance_variable_get("@#{key}_hash")
    end

    def collection_field_mapping
      ActiveSupport::Deprecation.warn(
        'Creating Collections using the collection_field_mapping will no longer be supported as of version Bulkrax v2.' \
        ' Please configure Bulkrax to use related_parents_field_mapping and related_children_field_mapping instead.'
      )
      Bulkrax.collection_field_mapping[self.entry_class.to_s]&.to_sym || :collection
    end

    def model_field_mappings
      model_mappings = Bulkrax.field_mappings[self.class.to_s]&.dig('model', :from) || []
      model_mappings |= ['model']

      model_mappings
    end

    def perform_method
      if self.validate_only
        'perform_now'
      else
        'perform_later'
      end
    end

    def visibility
      @visibility ||= self.parser_fields['visibility'] || 'open'
    end

    def create_collections
      raise StandardError, 'must be defined' if importer?
    end

    def create_works
      raise StandardError, 'must be defined' if importer?
    end

    def create_file_sets
      raise StandardError, 'must be defined' if importer?
    end

    # Optional, define if using browse everything for file upload
    def retrieve_cloud_files(files); end

    def write_import_file(file)
      path = File.join(path_for_import, file.original_filename)
      FileUtils.mv(
        file.path,
        path
      )
      path
    end

    # Base path for imported and exported files
    def base_path(type = 'import')
      ENV['HYKU_MULTITENANT'] ? File.join(Bulkrax.send("#{type}_path"), Site.instance.account.name) : Bulkrax.send("#{type}_path")
    end

    # Path where we'll store the import metadata and files
    #  this is used for uploaded and cloud files
    def path_for_import
      @path_for_import = File.join(base_path, importerexporter.path_string)
      FileUtils.mkdir_p(@path_for_import) unless File.exist?(@path_for_import)
      @path_for_import
    end

    def setup_export_file
      raise StandardError, 'must be defined' if exporter?
    end

    def write_files
      raise StandardError, 'must be defined' if exporter?
    end

    def importer?
      importerexporter.is_a?(Bulkrax::Importer)
    end

    def exporter?
      importerexporter.is_a?(Bulkrax::Exporter)
    end

    # @param limit [Integer] limit set on the importerexporter
    # @param index [Integer] index of current iteration
    # @return [boolean]
    def limit_reached?(limit, index)
      return false if limit.nil? || limit.zero? # no limit
      index >= limit
    end

    # Override to add specific validations
    def valid_import?
      true
    end

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

    def write
      write_files
      zip
    end

    def unzip(file_to_unzip)
      WillowSword::ZipPackage.new(file_to_unzip, importer_unzip_path).unzip_file
    end

    def zip
      FileUtils.rm_rf(exporter_export_zip_path)
      WillowSword::ZipPackage.new(exporter_export_path, exporter_export_zip_path).create_zip
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
    def import_file_path
      @import_file_path ||= real_import_file_path
    end

    private

    def real_import_file_path
      return importer_unzip_path if file? && zip?

      parser_fields['import_file_path']
    end
  end
end
