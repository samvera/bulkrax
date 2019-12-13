# frozen_string_literal: true

module Bulkrax
  class ApplicationController < ActionController::Base
    helper Rails.application.class.helpers
    protect_from_forgery with: :exception
  end
end
