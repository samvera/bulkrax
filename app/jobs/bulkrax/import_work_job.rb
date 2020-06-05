# frozen_string_literal: true

module Bulkrax
  class ImportWorkJob < ApplicationJob
    queue_as :import

    # rubocop:disable Rails/SkipsModelValidations
    def perform(*args)
      entry = Entry.find(args[0])
      build_result = entry.build
      if build_result.present?
        ImporterRun.find(args[1]).increment!(:processed_records)
        ImporterRun.find(args[1]).decrement!(:enqueued_records) # rubocop:disable Style/IdenticalConditionalBranches
      else
        # do not retry here because whatever parse error kept you from creating a work will likely
        # keep preventing you from doing so.
        ImporterRun.find(args[1]).increment!(:failed_records)
        ImporterRun.find(args[1]).decrement!(:enqueued_records) # rubocop:disable Style/IdenticalConditionalBranches
      end
      entry.save!
    rescue Bulkrax::CollectionsCreatedError
      reschedule(args[0], args[1])
    end
    # rubocop:enable Rails/SkipsModelValidations

    def reschedule(entry_id, run_id)
      ImportWorkJob.set(wait: 1.minute).perform_later(entry_id, run_id)
    end
  end
end
