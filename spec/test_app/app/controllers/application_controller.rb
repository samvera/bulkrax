# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Adds a few additional behaviors into the application controller
  include Blacklight::Controller
  include Hyrax::ThemedLayoutController
  with_themed_layout '1_column'
  skip_after_action :discard_flash_if_xhr
  protect_from_forgery with: :exception

end
