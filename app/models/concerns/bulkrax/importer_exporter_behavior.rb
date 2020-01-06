# frozen_string_literal: true

module Bulkrax
  module ImporterExporterBehavior
    extend ActiveSupport::Concern

    def parser
      @parser ||= self.parser_klass.constantize.new(self)
    end

    def last_imported_at
      @last_imported_at ||= self.importer_runs.last&.created_at
    end

    def next_import_at
      (last_imported_at || Time.current) + frequency.to_seconds if schedulable? && last_imported_at.present?
    end

    def increment_counters(index)
      current_importer_run.total_work_entries = index + 1 unless limit.to_i.positive? || parser.total.positive?
      current_importer_run.enqueued_records = index + 1
      current_importer_run.save!
    end
  end
end
