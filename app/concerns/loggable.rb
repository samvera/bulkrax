# frozen_string_literal: true

module Loggable
  extend ActiveSupport::Concern

  def log_created(obj)
    log_action('Created', obj)
  end

  def log_updated(obj)
    log_action('Updated', obj)
  end

  def log_deleted_fs(obj)
    msg = "Deleted All Files from #{obj.id}"
    Rails.logger.info("#{msg} (#{Array(obj.attributes[work_identifier]).first})")
  end

  private

  def log_action(action, obj)
    msg = "#{action} #{obj.class.model_name.human} #{obj.id}"
    Rails.logger.info("#{msg} (#{Array(obj.attributes[work_identifier]).first})")
  end
end
