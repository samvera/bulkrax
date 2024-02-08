# frozen_string_literal: true

require 'iso8601'

module Bulkrax
  class Importer < ApplicationRecord # rubocop:disable Metrics/ClassLength
    include Bulkrax::ImporterExporterBehavior
    include Bulkrax::StatusInfo

    serialize :parser_fields, JSON
    serialize :field_mapping, JSON

    belongs_to :user
    has_many :importer_runs, dependent: :destroy
    has_many :entries, as: :importerexporter, dependent: :destroy

    validates :name, presence: true
    validates :admin_set_id, presence: true if defined?(::Hyrax)
    validates :parser_klass, presence: true

    delegate :valid_import?, :write_errored_entries_file, :visibility, to: :parser

    attr_accessor :only_updates, :file_style, :file
    attr_writer :current_run

    def self.safe_uri_filename(uri)
      r = Faraday.head(uri.to_s)
      return CGI.parse(r.headers['content-disposition'])["filename"][0].delete("\"")
    rescue
      filename = File.basename(uri.to_s)
      filename.delete!('/')
      filename.presence || SecureRandom.uuid
    end

    def status
      if self.validate_only
        'Validated'
      else
        super
      end
    end

    def record_status
      importer_run = ImporterRun.find(current_run.id) # make sure fresh
      return if importer_run.enqueued_records.positive? # still processing
      if importer_run.failed_records.positive?
        if importer_run.invalid_records.present?
          e = Bulkrax::ImportFailed.new('Failed with Invalid Records', importer_run.invalid_records.split("\n"))
          importer_run.importer.set_status_info(e)
        else
          importer_run.importer.set_status_info('Complete (with failures)')
        end
      else
        importer_run.importer.set_status_info('Complete')
      end
    end

    # If field_mapping is empty, setup a default based on the export_properties
    def mapping
      # rubocop:disable Style/IfUnlessModifier
      @mapping ||= if self.field_mapping.blank? || self.field_mapping == [{}]
                     if parser.import_fields.present? || self.field_mapping == [{}]
                       default_field_mapping
                     end
                   else
                     default_field_mapping.merge(self.field_mapping)
                   end

      # rubocop:enable Style/IfUnlessModifier
    end

    def default_field_mapping
      return self.field_mapping if parser.import_fields.nil?

      ActiveSupport::HashWithIndifferentAccess.new(
        parser.import_fields.reject(&:nil?).map do |m|
          Bulkrax.default_field_mapping.call(m)
        end.inject(:merge)
      )
    end

    def parser_fields
      self[:parser_fields] || {}
    end

    def self.frequency_enums
      # these duration values use ISO 8601 Durations (https://en.wikipedia.org/wiki/ISO_8601#Durations)
      # TLDR; all durations are prefixed with 'P' and the parts are a number with the type of duration.
      # i.e. P1Y2M3W4DT5H6M7S == 1 Year, 2 Months, 3 Weeks, 4 Days, 5 Hours, 6 Minutes, 7 Seconds
      [['Daily', 'P1D'], ['Monthly', 'P1M'], ['Yearly', 'P1Y'], ['Once (on save)', 'PT0S']]
    end

    def frequency=(frequency)
      self[:frequency] = ISO8601::Duration.new(frequency).to_s
    end

    def frequency
      f = self[:frequency] || "PT0S"
      ISO8601::Duration.new(f)
    end

    def schedulable?
      frequency.to_seconds != 0
    end

    def current_run
      return @current_run if @current_run.present?

      @current_run = self.importer_runs.create!
      return @current_run if file? && zip?

      entry_counts = {
        total_work_entries: self.limit || parser.works_total,
        total_collection_entries: parser.collections_total,
        total_file_set_entries: parser.file_sets_total
      }
      @current_run.update!(entry_counts)

      @current_run
    end

    def last_run
      @last_run ||= self.importer_runs.last
    end

    def failed_entries?
      entries.failed.any?
    end

    def failed_statuses
      @failed_statuses ||= Bulkrax::Status.latest_by_statusable
                                          .includes(:statusable)
                                          .where('bulkrax_statuses.statusable_id IN (?) AND bulkrax_statuses.statusable_type = ? AND status_message = ?', self.entries.pluck(:id), 'Bulkrax::Entry', 'Failed')
    end

    def failed_messages
      failed_statuses.each_with_object({}) do |e, i|
        i[e.error_message] ||= []
        i[e.error_message] << e.id
      end
    end

    def completed_statuses
      @completed_statuses ||= Bulkrax::Status.latest_by_statusable
                                             .includes(:statusable)
                                             .where('bulkrax_statuses.statusable_id IN (?) AND bulkrax_statuses.statusable_type = ? AND status_message = ?', self.entries.pluck(:id), 'Bulkrax::Entry', 'Complete')
    end

    def seen
      @seen ||= {}
    end

    def replace_files
      self.parser_fields['replace_files']
    end

    def update_files
      self.parser_fields['update_files']
    end

    def remove_and_rerun
      self.parser_fields['remove_and_rerun']
    end

    def metadata_only?
      parser.parser_fields['metadata_only'] == true
    end

    def import_works
      import_objects(['work'])
    end

    def import_collections
      import_objects(['collection'])
    end

    def import_file_sets
      import_objects(['file_set'])
    end

    def import_relationships
      import_objects(['relationship'])
    end

    DEFAULT_OBJECT_TYPES = %w[collection work file_set relationship].freeze

    def import_objects(types_array = nil)
      self.only_updates ||= false
      self.save if self.new_record? # Object needs to be saved for statuses
      types = types_array || DEFAULT_OBJECT_TYPES
      if remove_and_rerun
        self.entries.find_each do |e|
          e.factory.find&.destroy!
          e.destroy!
        end
      end
      parser.create_objects(types)
    rescue StandardError => e
      set_status_info(e)
    end

    # Prepend the base_url to ensure unique set identifiers
    # @todo - move to parser, as this is OAI specific
    def unique_collection_identifier(id)
      "#{self.parser_fields['base_url'].split('/')[2]}_#{id}"
    end

    # The format for metadata for the incoming import; corresponds to an Entry class
    def import_metadata_format
      [['CSV', 'Bulkrax::CsvEntry'], ['RDF (N-Triples)', 'Bulkrax::RdfEntry']]
    end

    # The type of metadata for the incoming import, either one file for all works, or one file per work
    # def import_metadata_type
    #   [['Single Metadata File for all works', 'single'], ['Multiple Files, one per Work', 'multi']]
    # end

    # If the import data is zipped, unzip it to this path
    def importer_unzip_path
      @importer_unzip_path ||= File.join(parser.base_path, "import_#{path_string}")
    end

    def errored_entries_csv_path
      @errored_entries_csv_path ||= File.join(parser.base_path, "import_#{path_string}_errored_entries.csv")
    end

    def path_string
      "#{self.id}_#{self.created_at.strftime('%Y%m%d%H%M%S')}_#{self.importer_runs.last.id}"
    rescue
      "#{self.id}_#{self.created_at.strftime('%Y%m%d%H%M%S')}"
    end
  end
end
