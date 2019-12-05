module Bulkrax
  class ApplicationParser

    attr_accessor :importerexporter, :total
    delegate :only_updates, :limit, :current_exporter_run, :current_importer_run, :errors,
      :seen, :increment_counters, :parser_fields, :user, :exporter_export_path, :exporter_export_zip_path, 
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
    def run
      raise 'must be defined'
    end

    # @api
    def entry_class
      raise 'must be defined'
    end

    # @api
    def records(opts = {})
      raise 'must be defined'
    end

    def import_fields
      raise 'must be defined'
    end

    def importer?
      importerexporter.is_a?(Bulkrax::Importer)
    end

    def exporter
      importerexporter.is_a?(Bulkrax::Exporter)
    end

    # Override to add specific validations
    def validate_import; end

    def find_or_create_entry(entryclass, identifier, type, raw_metadata = nil)
      entryclass.where(
        importerexporter_id: importerexporter.id,
        importerexporter_type: type,
        identifier: identifier,
        raw_metadata: raw_metadata
      ).first_or_create!
    end

    def write
      write_files
      zip
    end

    def zip
      WillowSword::ZipPackage.new(exporter_export_path, exporter_export_zip_path).create_zip
    end

    def record(identifier, opts = {})
      return @record if @record

      @record = entry_class.new(self, identifier)
      @record.build
      return @record
    end

    def total
      0
    end
  end
end
