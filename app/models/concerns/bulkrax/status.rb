# frozen_string_literal: true
module Bulkrax
  module Status
    extend ActiveSupport::Concern
    def status
      if self.last_error_at.present?
        'failed'
      elsif self.last_succeeded_at.present?
        'succeeded'
      else
        'waiting'
      end
    end

    def status_at
      case status
      when 'succeeded'
        self.last_succeeded_at
      when 'failed'
        self.last_error_at
      end
    end

    def status_info(e = nil)
      if e.nil?
        self.last_error = nil
        self.last_error_at = nil
        self.last_succeeded_at = Time.current
      else
        self.last_error =  { error_class: e.class.to_s, error_message: e.message, error_trace: e.backtrace }
        self.last_error_at = Time.current
      end
      self.save!
    end
  end
end
