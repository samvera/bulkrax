# frozen_string_literal: true
module Bulkrax
  module StatusInfo
    extend ActiveSupport::Concern

    def current_status
      last_status = self.statuses.last
      last_status if last_status && last_status.runnable == last_run
    end

    def failed?
      current_status&.status_message == 'Failed'
    end

    def status
      current_status&.status_message || 'Pending'
    end

    def status_at
      current_status&.created_at
    end

    def status_info(e = nil)
      if e.nil?
        self.statuses.create!(status_message: 'Complete', runnable: last_run)
      elsif e.is_a?(String)
        self.statuses.create!(status_message: e, runnable: last_run)
      else
        self.statuses.create!(status_message: 'Failed', runnable: last_run, error_class: e.class.to_s, error_message: e.message, error_backtrace: e.backtrace)
      end
    end

    # api compatible with previous error structure
    def last_error
      if current_status && current_status.error_class.present?
        {
          error_class: current_status.error_class,
          error_message: current_status.error_message,
          error_trace: current_status.error_backtrace
        }.with_indifferent_access
      else
        super
      end
    end
  end
end
