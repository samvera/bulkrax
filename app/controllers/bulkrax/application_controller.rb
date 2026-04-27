# frozen_string_literal: true

module Bulkrax
  class ApplicationController < ::ApplicationController
    helper Rails.application.class.helpers
    protect_from_forgery with: :exception

    # Rescue CanCan::AccessDenied in all Bulkrax controllers.  HTML requests are
    # redirected to the host-app root with an alert; JSON requests receive a 403
    # response.  Defining the handler here (rather than in individual controllers)
    # keeps error handling in one place and consistent across all resources.
    rescue_from CanCan::AccessDenied do |exception|
      respond_to do |format|
        format.html { redirect_to main_app.root_path, alert: exception.message }
        format.json { render json: { error: exception.message }, status: :forbidden }
      end
    end
  end
end
