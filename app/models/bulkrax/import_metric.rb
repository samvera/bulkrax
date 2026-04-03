# frozen_string_literal: true

module Bulkrax
  class ImportMetric < ApplicationRecord
    self.table_name = 'bulkrax_import_metrics'

    belongs_to :importer, class_name: 'Bulkrax::Importer', optional: true
    belongs_to :user, optional: true

    validates :metric_type, presence: true,
              inclusion: { in: %w[funnel validation import_outcome feedback timing] }
    validates :event, presence: true

    scope :funnel,          -> { where(metric_type: 'funnel') }
    scope :validations,     -> { where(metric_type: 'validation') }
    scope :import_outcomes, -> { where(metric_type: 'import_outcome') }
    scope :feedback,        -> { where(metric_type: 'feedback') }
    scope :timing,          -> { where(metric_type: 'timing') }
    scope :in_range,        ->(from, to) { where(created_at: from..to) }

    # Fire-and-forget recording. NEVER raises.
    def self.record(metric_type:, event:, importer: nil, user: nil, session_id: nil, payload: {})
      create(
        metric_type: metric_type,
        event: event,
        importer: importer,
        user: user,
        session_id: session_id,
        payload: payload
      )
    rescue StandardError => e
      Rails.logger.warn("Bulkrax::ImportMetric.record failed: #{e.message}")
      nil
    end
  end
end
