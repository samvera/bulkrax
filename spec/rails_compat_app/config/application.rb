# frozen_string_literal: true

require 'bundler/setup'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'active_job/railtie'
require 'kaminari'
require 'bulkrax'

module RailsCompatApp
  class Application < Rails::Application
    config.root = File.expand_path('..', __dir__)
    config.load_defaults "#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}"
    config.eager_load = false
    config.secret_key_base = 'bulkrax-compatibility-test-only'
    config.logger = Logger.new(File::NULL)
    config.active_record.schema_format = :ruby
  end
end
