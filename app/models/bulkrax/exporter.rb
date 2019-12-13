# frozen_string_literal: true

require 'fileutils'

module Bulkrax
  class Exporter < ApplicationRecord
    include Bulkrax::ImporterExporterBehavior

    serialize :field_mapping, JSON

    belongs_to :user
    has_many :exporter_runs, dependent: :destroy, foreign_key: 'exporter_id'
    has_many :entries, as: :importerexporter

    validates :name, presence: true
    validates :parser_klass, presence: true

    delegate :write, :create_from_collection, :create_from_importer, to: :parser

    def export
      current_exporter_run && setup_export_path
      if self.export_from == 'collection'
        create_from_collection
      elsif self.export_from == 'import'
        create_from_importer
      end
    end

    def mapping
      @mapping ||= self.field_mapping || export_properties.map { |m| Bulkrax.default_field_mapping.call(m) }.inject(:merge)
    end

    def export_from_list
      [['Collection', 'collection'], ['Import', 'import']]
    end

    def export_type_list
      [['Metadata Only', 'metadata'], ['Metadata and Files', 'full']]
    end

    def importers_list
      Importer.all.map { |i| [i.name, i.id] }
    end

    def current_exporter_run
      @current_exporter_run ||= self.exporter_runs.create!(total_work_entries: self.limit)
    end

    def setup_export_path
      FileUtils.mkdir_p(exporter_export_path)
    end

    def exporter_export_path
      @exporter_export_path ||= File.join(Bulkrax.export_path, self.id.to_s, self.exporter_runs.last.id.to_s)
    end

    def exporter_export_zip_path
      @exporter_export_zip_path ||= File.join(ENV.fetch('RAILS_TMP', Dir.tmpdir).to_s, "export_#{self.id}_#{self.exporter_runs.last.id}.zip")
    rescue
      @exporter_export_zip_path ||= File.join(ENV.fetch('RAILS_TMP', Dir.tmpdir).to_s, "export_#{self.id}_0.zip")
    end

    def export_properties
      properties = Hyrax.config.registered_curation_concern_types.map { |work| work.constantize.properties.keys }.flatten.uniq.sort
      properties.reject { |prop| Bulkrax.reserved_properties.include?(prop) }
    end
  end
end
