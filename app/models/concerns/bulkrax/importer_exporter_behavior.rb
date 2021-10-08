# frozen_string_literal: true

module Bulkrax
  module ImporterExporterBehavior
    extend ActiveSupport::Concern

    def parser
      @parser ||= parser_class.new(self)
    end

    def parser_class
      self.parser_klass.constantize
    end

    def last_imported_at
      @last_imported_at ||= self.importer_runs.last&.created_at
    end

    def next_import_at
      (last_imported_at || Time.current) + frequency.to_seconds if schedulable? && last_imported_at.present?
    end

    def increment_counters(index, collection = false)
      # Only set the totals if they were not set on initialization
      if collection
        current_run.total_collection_entries = index + 1 unless parser.collections_total.positive?
      else
        # TODO: differentiate between work and collection counts for exporters
        current_run.total_work_entries = index + 1 unless limit.to_i.positive? || parser.total.positive?
      end
      current_run.enqueued_records = index + 1
      current_run.save!
    end

    def keys_without_numbers(keys)
      keys.map { |key| key_without_numbers(key) }
    end

    def key_without_numbers(key)
      key.gsub(/_\d+/, '').sub(/^\d+_/, '')
    end

    # Is this a file?
    def file?
      parser_fields&.[]('import_file_path') && File.file?(parser_fields['import_file_path'])
    end

    # Is this a zip file?
    def zip?
      parser_fields&.[]('import_file_path') && MIME::Types.type_for(parser_fields['import_file_path']).include?('application/zip')
    end
  end
end
