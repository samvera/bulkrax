module Bulkrax::Concerns::ImporterExporterBehavior
  extend ActiveSupport::Concern

  def parser
    @parser ||= self.parser_klass.constantize.new(self)
  end

  def last_imported_at
    @last_imported_at ||= self.importer_runs.last&.created_at
  end

  def next_import_at
    (last_imported_at || Time.current) + frequency.to_seconds if schedulable? and last_imported_at.present?
  end

  def increment_counters(index)
    if limit.to_i > 0
      current_importer_run.total_records = limit
    elsif parser.total > 0
      current_importer_run.total_records = parser.total
    else
      current_importer_run.total_records = index + 1
    end
    current_importer_run.enqueued_records = index + 1
    current_importer_run.save!
  end
end
