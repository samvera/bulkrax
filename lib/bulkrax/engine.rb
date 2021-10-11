# frozen_string_literal: true

require 'oai'

module Bulkrax
  class Engine < ::Rails::Engine
    isolate_namespace Bulkrax
    initializer :append_migrations do |app|
      if !app.root.to_s.match(root.to_s) && app.root.join('db/migrate').children.none? { |path| path.fnmatch?("*.bulkrax.rb") }
        config.paths["db/migrate"].expanded.each do |expanded_path|
          app.config.paths["db/migrate"] << expanded_path
        end
      end
    end

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot, dir: 'spec/factories'
    end

    config.after_initialize do
      my_engine_root = Bulkrax::Engine.root.to_s
      paths = ActionController::Base.view_paths.collect(&:to_s)
      hyrax_path = paths.detect { |path| path.match(/\/hyrax-[\d\.]+.*/) }
      paths = if hyrax_path
                paths.insert(paths.index(hyrax_path), my_engine_root + '/app/views')
              else
                paths.insert(0, my_engine_root + '/app/views')
              end
      ActionController::Base.view_paths = paths
    end
  end
end
