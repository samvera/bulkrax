# frozen_string_literal: true

module Bulkrax
  class ApplicationParser
    attr_accessor :importerexporter
    alias importer importerexporter
    alias exporter importerexporter
    delegate :only_updates, :limit, :current_run, :errors,
             :seen, :increment_counters, :parser_fields, :user,
             :exporter_export_path, :exporter_export_zip_path, :importer_unzip_path, :validate_only,
             :status, :status_info, :status_at,
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
      @source_identifier ||= identifier_hash.values.first&.[]("from")&.first&.to_sym || :source_identifier
    end

    def work_identifier
      @work_identifier ||= identifier_hash.keys.first&.to_sym || :source
    end

    def identifier_hash
      @identifier_hash ||= importerexporter.mapping.select do |_, h|
        h.key?("source_identifier")
      end
      raise StandardError, "more than one source_identifier declared: #{@identifier_hash.keys.join(', ')}" if @identifier_hash.length > 1

      @identifier_hash
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

    # Path where we'll store the import metadata and files
    #  this is used for uploaded and cloud files
    def path_for_import
      @path_for_import = File.join(Bulkrax.import_path, importerexporter.path_string)
      FileUtils.mkdir_p(@path_for_import) unless File.exist?(@path_for_import)
      @path_for_import
    end

    # Optional, only used by certain parsers
    # Other parsers should override with a custom or empty method
    # Will be skipped unless the #record is a Hash
    def create_parent_child_relationships
      parents.each do |key, value|
        parent = entry_class.where(
          identifier: key,
          importerexporter_id: importerexporter.id,
          importerexporter_type: 'Bulkrax::Importer'
        ).first

        # not finding the entries here indicates that the given identifiers are incorrect
        # in that case we should log that
        children = value.map do |child|
          entry_class.where(
            identifier: child,
            importerexporter_id: importerexporter.id,
            importerexporter_type: 'Bulkrax::Importer'
          ).first
        end.compact.uniq

        if parent.present? && (children.length != value.length)
          # Increment the failures for the number we couldn't find
          # Because all of our entries have been created by now, if we can't find them, the data is wrong
          Rails.logger.error("Expected #{value.length} children for parent entry #{parent.id}, found #{children.length}")
          break if children.empty?
          Rails.logger.warn("Adding #{children.length} children to parent entry #{parent.id} (expected #{value.length})")
        end
        parent_id = parent.id
        child_entry_ids = children.map(&:id)
        ChildRelationshipsJob.perform_later(parent_id, child_entry_ids, current_run.id)
      end
    rescue StandardError => e
      status_info(e)
    end

    def parents
      @parents ||= setup_parents
    end

    def setup_parents
      pts = []
      records.each do |record|
        r = if record.respond_to?(:to_h)
              record.to_h
            else
              record
            end
        next unless r.is_a?(Hash)
        children = if r[:children].is_a?(String)
                     r[:children].split(/\s*[:;|]\s*/)
                   else
                     r[:children]
                   end
        next if children.blank?
        pts << {
          r[source_identifier] => children
        }
      end
      pts.blank? ? pts : pts.inject(:merge)
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
      ['title', source_identifier]
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
        if file? && zip?
          unzip(parser_fields['import_file_path'])
          return importer_unzip_path
        else
          parser_fields['import_file_path']
        end
      end
  end
end
