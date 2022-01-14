# frozen_string_literal: true
module Bulkrax
  module StatusInfo
    extend ActiveSupport::Concern

    included do
      has_many :statuses, as: :statusable, dependent: :destroy
      has_one :latest_status,
              -> { merge(Status.latest_by_statusable) },
              as: :statusable,
              class_name: "Bulkrax::Status",
              inverse_of: :statusable
    end

    def current_status
      last_status = self.statuses.last
      last_status if last_status && last_status.runnable == last_run
    end

    def failed?
      current_status&.status_message&.match(/fail/i)
    end

    def succeeded?
      current_status&.status_message&.match(/^Complete$/)
    end

    def status
      current_status&.status_message || 'Pending'
    end

    def status_at
      current_status&.created_at
    end

    def status_info(e = nil, current_run = nil)
      if e.nil?
        self.statuses.create!(status_message: 'Complete', runnable: current_run || last_run)
      elsif e.is_a?(String)
        self.statuses.create!(status_message: e, runnable: current_run || last_run)
      else
        self.statuses.create!(status_message: 'Failed', runnable: current_run || last_run, error_class: e.class.to_s, error_message: e.message, error_backtrace: e.backtrace)
      end
    end

    # api compatible with previous error structure
    def last_error
      return unless current_status && current_status.error_class.present?
      {
        error_class: current_status.error_class,
        error_message: current_status.error_message,
        error_trace: current_status.error_backtrace
      }.with_indifferent_access
    end
  end
end
