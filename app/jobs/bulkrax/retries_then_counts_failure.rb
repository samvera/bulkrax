# frozen_string_literal: true

module Bulkrax
  # Retries an import job that raises, then counts its record as failed once the
  # retries run out, so the run's enqueued_records still reaches zero.
  #
  # Including jobs take (entry_id, importer_run_id, ...) and define FAILED_COUNTER.
  module RetriesThenCountsFailure
    extend ActiveSupport::Concern

    included do
      # Waits 5, 10, 20 and then 40 minutes between the five attempts.
      retry_on StandardError, wait: ->(executions) { (5 * (2**(executions - 1))).minutes }, attempts: 5 do |job, error|
        job.count_as_failed(*job.arguments.first(2), error)
      end
    end

    # One transaction, so a failure part way through leaves nothing counted for a
    # later retry of this job to count again.
    def count_as_failed(entry_id, importer_run_id, error)
      importer_run = ImporterRun.find(importer_run_id)
      ImporterRun.transaction do
        Entry.find_by(id: entry_id)&.set_status_info(error, importer_run)
        # rubocop:disable Rails/SkipsModelValidations
        ImporterRun.increment_counter(:failed_records, importer_run.id)
        ImporterRun.increment_counter(self.class::FAILED_COUNTER, importer_run.id)
        # rubocop:enable Rails/SkipsModelValidations
        ImporterRun.decrement_enqueued_records(importer_run.id)
        importer_run.importer.tap { |importer| importer.current_run = importer_run }.record_status
      end
    end
  end
end
