# frozen_string_literal: true

module Bulkrax
  # Product metrics for the guided import. Recording must never interrupt an
  # import, so the writers log failures instead of raising.
  class ImportMetric < ApplicationRecord
    METRIC_TYPES = %w[funnel validation import_outcome feedback timing].freeze

    belongs_to :importer, optional: true
    belongs_to :importer_run, optional: true
    belongs_to :user, optional: true

    if Rails.version < '7.1'
      serialize :payload, JSON
    else
      serialize :payload, coder: JSON
    end

    validates :metric_type, inclusion: { in: METRIC_TYPES }
    validates :event, presence: true

    scope :validations,     -> { where(metric_type: 'validation') }
    scope :import_outcomes, -> { where(metric_type: 'import_outcome') }
    scope :in_range,        ->(from, to) { where(created_at: from..to) }

    def self.record(payload: {}, **attrs)
      create!(payload: payload, **attrs)
    rescue StandardError => e
      log_failure(e)
    end

    # record_status runs once per finished job, so a run can be reported
    # finished several times; each report overwrites the run's single row.
    def self.record_import_outcome(run, payload: {}, **attrs)
      attempts = 0
      begin
        attempts += 1
        metric = find_or_initialize_by(importer_run_id: run.id, metric_type: 'import_outcome')
        metric.update!(event: 'import_complete', payload: payload, **attrs)
        metric
      rescue ActiveRecord::RecordNotUnique
        retry if attempts < 2
        raise
      end
    rescue StandardError => e
      log_failure(e)
    end

    # The table check lets importers be destroyed on a host that has not run
    # this migration yet, even with metrics disabled.
    def self.detach_from(**owner)
      return unless table_exists?

      where(owner).update_all(owner.transform_values { nil }) # rubocop:disable Rails/SkipsModelValidations
    end

    def self.log_failure(error)
      Rails.logger.warn("Bulkrax::ImportMetric not recorded: #{error.class}: #{error.message}")
      nil
    end
  end
end
