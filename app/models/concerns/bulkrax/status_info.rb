# frozen_string_literal: true
module Bulkrax
  module StatusInfo
    extend ActiveSupport::Concern

    def current_status
      last_status = self.statuses.last
      if last_status && last_status.runnable == last_run
        last_status
      end
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
        self.statuses.create!(status_message: 'Failed', runnable: last_run, success: true)
      else
        self.statuses.create!(status_message: 'Processing', runnable: last_run, success: false, error_class: e.class.to_s, error_message: e.message, error_trace: e.backtrace)
      end
    end
  end
end
