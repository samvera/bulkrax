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
      scope :failed, -> { where(status_message: 'Failed') }
      scope :complete, -> { where(status_message: 'Complete') }
      scope :pending, -> { where(status_message: 'Pending') }
      scope :skipped, -> { where(status_message: 'Skipped') }
    end

    def current_status
      last_status = self.statuses.last
      last_status if last_status && last_status.runnable == last_run
    end

    def failed?
      current_status&.status_message&.eql?('Failed')
    end

    def succeeded?
      current_status&.status_message&.match(/^Complete$/)
    end

    def skipped?
      current_status&.status_message&.match('Skipped')
    end

    def status
      current_status&.status_message || 'Pending'
    end

    def status_at
      current_status&.created_at
    end

    def set_status_info(e = nil, current_run = nil)
      runnable = current_run || last_run
      if e.nil?
        self.statuses.create!(status_message: 'Complete', runnable: runnable)
      elsif e.is_a?(String)
        self.statuses.create!(status_message: e, runnable: runnable)
      else
        self.statuses.create!(status_message: 'Failed', runnable: runnable, error_class: e.class.to_s, error_message: e.message, error_backtrace: e.backtrace)
      end
    rescue => e
      save_with_placeholder_to_capture_status(e, runnable)
    end

    alias status_info set_status_info

    deprecation_deprecate status_info: "Favor Bulkrax::StatusInfo.set_status_info.  We will be removing .status_info in Bulkrax v6.0.0"

    def save_with_placeholder_to_capture_status(e, runnable)
      case e.class.to_s
      when 'ActiveRecord::RecordInvalid'
        runnable.user = current_or_placeholder_user if runnable.user.nil?
        runnable.admin_set_id = placeholder_admin_set_id if runnable.admin_set_id.nil?
        runnable.name = 'Placeholder Name' if runnable.name.nil?
        runnable.parser_klass = Bulkrax::CsvParser if runnable.parser_klass.nil?
        runnable.save!
        runnable.errors.each do |error|
          set_status_info(error, runnable)
        end
      when 'ActiveRecord::RecordNotSaved'
        runnable.user = current_or_placeholder_user if runnable.user.nil?
        runnable.admin_set_id = placeholder_admin_set_id if runnable.admin_set_id.nil?
        runnable.name = 'Placeholder Name' if runnable.name.nil?
        runnable.parser_klass = Bulkrax::CsvParser if runnable.parser_klass.nil?
        runnable.save!
        runnable.errors.each do |error|
          set_status_info(error, runnable)
        end
      end
    end

    def current_or_placeholder_user
      placeholder_user = User.new(display_name: 'Placeholder User')
      placeholder_user.save!
      @current_user.presence || placeholder_user
    end

    def placeholder_admin_set_id
      placeholder_admin_set = AdminSet.new(title: ['Placeholder Admin Set'])
      placeholder_admin_set.save!
      placeholder_admin_set.id
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
