# frozen_string_literal: true

module Bulkrax
  class ScheduleRelationshipsJob < ApplicationJob
    # Relationships wait until no entry is Pending. If no entry has finished for
    # STALL_LIMIT, a stuck entry or a backed-up queue is holding them, so relate
    # the parents that are ready and check again every STALLED_CHECK_WAIT for
    # entries that finish later, until GIVE_UP_LIMIT. CreateRelationshipsJob
    # deletes each pending relationship it links, so every pass handles only
    # what is left. Re-running an entry schedules this job again.
    STALL_LIMIT = 24.hours
    STALLED_CHECK_WAIT = 1.hour
    GIVE_UP_LIMIT = 7.days
    # Statuses that mean an entry finished. CreateRelationshipsJob writes some
    # relationship errors as their text, which this leaves out, and others as
    # Failed, which ready_parents keeps from repeating.
    FINISHED_STATUSES = %w[Complete Failed Skipped Deleted].freeze

    def perform(importer_id:)
      importer = Importer.find(importer_id)
      pending = importer.entries.pending
      return create_relationships(importer, importer.last_run.parents) unless pending.exists?

      last_progress = last_progress_at(importer)
      return reschedule(importer_id) if last_progress > STALL_LIMIT.ago

      giving_up = last_progress < GIVE_UP_LIMIT.ago
      log_stall(importer_id, pending, giving_up: giving_up)
      ScheduleRelationshipsJob.set(wait: STALLED_CHECK_WAIT).perform_later(importer_id: importer_id) unless giving_up
      create_relationships(importer, ready_parents(importer, pending))
    end

    def reschedule(importer_id)
      ScheduleRelationshipsJob.set(wait: 5.minutes).perform_later(importer_id: importer_id)
      false
    end

    private

    def log_stall(importer_id, pending, giving_up:)
      still_pending = "#{pending.count} #{'entry'.pluralize(pending.count)} still Pending"
      if giving_up
        Rails.logger.error("Bulkrax: no entry of importer #{importer_id} has finished in #{GIVE_UP_LIMIT.inspect}; " \
                           "creating the relationships that are ready and no longer checking, with #{still_pending}")
      else
        Rails.logger.warn("Bulkrax: no entry of importer #{importer_id} has finished in #{STALL_LIMIT.inspect}; " \
                          "creating the relationships that are ready with #{still_pending}")
      end
    end

    def create_relationships(importer, parent_ids)
      parent_ids.each do |parent_id|
        Bulkrax.relationship_job_class.constantize.perform_later(parent_identifier: parent_id,
                                                                 importer_run_id: importer.last_run.id)
      end
    end

    def last_progress_at(importer)
      [Status.where(statusable: importer.entries, status_message: FINISHED_STATUSES).maximum(:created_at),
       importer.last_run.created_at].compact.max
    end

    # Relating a parent fails, and marks it with the error, while the parent or
    # any child it still has to link is Pending. An identifier with no entry in
    # this import is an existing record, so it counts as ready. A relationship
    # that already failed waits for the final pass, so retrying it hourly does
    # not keep writing Failed statuses that look like progress. Known limit: a
    # cell that names a Pending row's record id rather than its source
    # identifier is not recognized as Pending.
    def ready_parents(importer, pending)
      pending_identifiers = pending.select(:identifier)
      relationships = importer.last_run.pending_relationships
      blocked = relationships.where(parent_id: pending_identifiers).or(relationships.where(child_id: pending_identifiers))
      relationships.pending.where.not(parent_id: blocked.select(:parent_id)).distinct.pluck(:parent_id)
    end
  end
end
