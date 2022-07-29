# frozen_string_literal: true
module Bulkrax
  class Exporter < ApplicationRecord
    include Bulkrax::ImporterExporterBehavior
    include Bulkrax::StatusInfo

    serialize :parser_fields, JSON
    serialize :field_mapping, JSON

    belongs_to :user
    has_many :exporter_runs, dependent: :destroy
    has_many :entries, as: :importerexporter, dependent: :destroy

    validates :name, presence: true
    validates :parser_klass, presence: true

    delegate :write, :create_from_collection, :create_from_importer, :create_from_worktype, :create_from_all, to: :parser

    def export
      current_run && setup_export_path
      case self.export_from
      when 'collection'
        create_from_collection
      when 'importer'
        create_from_importer
      when 'worktype'
        create_from_worktype
      when 'all'
        create_from_all
      end
    rescue StandardError => e
      status_info(e)
    end

    # #export_source accessors
    # Used in form to prevent it from getting confused as to which value to populate #export_source with.
    # Also, used to display the correct selected value when rendering edit form.
    def export_source_importer
      self.export_source if self.export_from == 'importer'
    end

    def export_source_collection
      self.export_source if self.export_from == 'collection'
    end

    def export_source_worktype
      self.export_source if self.export_from == 'worktype'
    end

    def date_filter
      self.start_date.present? || self.finish_date.present?
    end

    def include_thumbnails?
      self.include_thumbnails
    end

    def generated_metadata?
      self.generated_metadata
    end

    def work_visibility_list
      [
        ['Any', ''],
        [I18n.t('hyrax.visibility.open.text'), Hydra::AccessControls::AccessRight::VISIBILITY_TEXT_VALUE_PUBLIC],
        [I18n.t('hyrax.visibility.restricted.text'), Hydra::AccessControls::AccessRight::VISIBILITY_TEXT_VALUE_PRIVATE],
        [I18n.t('hyrax.visibility.authenticated.text', institution: I18n.t('hyrax.institution_name')), Hydra::AccessControls::AccessRight::VISIBILITY_TEXT_VALUE_AUTHENTICATED]
      ]
    end

    def workflow_status_list
      Sipity::WorkflowState.all.map { |s| [s.name&.titleize, s.name] }.uniq
    end

    # If field_mapping is empty, setup a default based on the export_properties
    def mapping
      @mapping ||= self.field_mapping ||
                   ActiveSupport::HashWithIndifferentAccess.new(
                     export_properties.map do |m|
                       Bulkrax.default_field_mapping.call(m)
                     end.inject(:merge)
                   ) ||
                   [{}]
    end

    def export_from_list
      [
        [I18n.t('bulkrax.exporter.labels.importer'), 'importer'],
        [I18n.t('bulkrax.exporter.labels.collection'), 'collection'],
        [I18n.t('bulkrax.exporter.labels.worktype'), 'worktype'],
        [I18n.t('bulkrax.exporter.labels.all'), 'all']
      ]
    end

    def export_type_list
      [
        [I18n.t('bulkrax.exporter.labels.metadata'), 'metadata'],
        [I18n.t('bulkrax.exporter.labels.full'), 'full']
      ]
    end

    def importers_list
      Importer.all.map { |i| [i.name, i.id] }
    end

    def current_run
      total = self.limit || parser.total
      @current_run ||= self.exporter_runs.create!(total_work_entries: total, enqueued_records: total)
    end

    def last_run
      @last_run ||= self.exporter_runs.last
    end

    def setup_export_path
      FileUtils.mkdir_p(exporter_export_path) unless File.exist?(exporter_export_path)
    end

    def exporter_export_path
      @exporter_export_path ||= File.join(parser.base_path('export'), self.id.to_s, self.exporter_runs.last.id.to_s)
    end

    def exporter_export_zip_path
      @exporter_export_zip_path ||= File.join(parser.base_path('export'), "export_#{self.id}_#{self.exporter_runs.last.id}")
    rescue
      @exporter_export_zip_path ||= File.join(parser.base_path('export'), "export_#{self.id}_0")
    end

    def exporter_export_zip_files
      @exporter_export_zip_files ||= Dir["#{exporter_export_zip_path}/**"].map { |zip| Array(zip.split('/').last) }
    end

    def export_properties
      properties = Hyrax.config.registered_curation_concern_types.map { |work| work.constantize.properties.keys }.flatten.uniq.sort
      properties.reject { |prop| Bulkrax.reserved_properties.include?(prop) }
    end

    def metadata_only?
      export_type == 'metadata'
    end

    def sort_zip_files(zip_files)
      zip_files.sort_by do |item|
        number = item.split('_').last.match(/\d+/)&.[](0) || 0.to_s
        sort_number = number.rjust(4, "0")

        sort_number
      end
    end
  end
end
