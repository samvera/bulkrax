require 'oai'

module Bulkrax
  class Engine < ::Rails::Engine
    isolate_namespace Bulkrax

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot, :dir => 'spec/factories'
    end

    config.after_initialize do
      my_engine_root = Bulkrax::Engine.root.to_s
      paths = ActionController::Base.view_paths.collect{|p| p.to_s}
      hyrax_path = paths.detect { |path| path.match('/hyrax-') }
      if hyrax_path
        paths = paths.insert(paths.index(hyrax_path), my_engine_root + '/app/views')
      else
        paths = paths.insert(0, my_engine_root + '/app/views')
      end
      ActionController::Base.view_paths = paths
    end

  end
end
