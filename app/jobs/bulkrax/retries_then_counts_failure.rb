# frozen_string_literal: true

module Bulkrax
  # Retries a job that raises, then counts its record as failed once the retries
  # run out, so the run's enqueued_records still reaches zero.
  #
  # Including jobs take (entry or entry_id, importer_run or importer_run_id, ...) and
  # define FAILED_COUNTER when their record type has its own failure counter.
  module RetriesThenCountsFailure
    extend ActiveSupport::Concern

    included do
      # Waits 5, 10, 20 and then 40 minutes between the five attempts.
      retry_on StandardError, wait: ->(executions) { (5 * (2**(executions - 1))).minutes }, attempts: 5 do |job, error|
        job.count_as_failed(*job.counted_ids, error)
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
        ImporterRun.increment_counter(failed_counter, importer_run.id) if failed_counter
        # rubocop:enable Rails/SkipsModelValidations
        ImporterRun.decrement_enqueued_records(importer_run.id)
        importer_run.importer.tap { |importer| importer.current_run = importer_run }.record_status
      end
    end

    # The entry and run ids, read from the serialized arguments because a job queued with
    # records cannot load them once the entry is deleted.
    def counted_ids
      serialize['arguments'].first(2).map do |argument|
        argument.is_a?(Hash) ? GlobalID.parse(argument['_aj_globalid'])&.model_id : argument
      end
    end

    def failed_counter
      self.class::FAILED_COUNTER if self.class.const_defined?(:FAILED_COUNTER)
    end
  end
end
