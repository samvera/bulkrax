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
      begin
        g.fixture_replacement :factory_bot, dir: 'spec/factories'
      rescue
        nil
      end
    end

    config.after_initialize do
      # We want to ensure that Bulkrax is earlier in the lookup for view_paths than Hyrax.  That is
      # we favor view in Bulkrax over those in Hyrax.
      if defined?(Hyrax)
        my_engine_root = Bulkrax::Engine.root.to_s
        hyrax_engine_root = Hyrax::Engine.root.to_s
        paths = ActionController::Base.view_paths.collect(&:to_s)
        hyrax_view_path = paths.detect { |path| path.match(%r{^#{hyrax_engine_root}}) }
        paths.insert(paths.index(hyrax_view_path), File.join(my_engine_root, 'app', 'views')) if hyrax_view_path
        ActionController::Base.view_paths = paths.uniq

        custom_query_strategies = {
          find_by_model_and_property_value: :find_single_or_nil
        }

        if defined?(::Goddess::CustomQueryContainer)
          strategies = ::Goddess::CustomQueryContainer.known_custom_queries_and_their_strategies
          strategies = strategies.merge(custom_query_strategies)
          ::Goddess::CustomQueryContainer.known_custom_queries_and_their_strategies = strategies
        end

        if defined?(::Frigg::CustomQueryContainer)
          strategies = ::Frigg::CustomQueryContainer.known_custom_queries_and_their_strategies
          strategies = strategies.merge(custom_query_strategies)
          ::Frigg::CustomQueryContainer.known_custom_queries_and_their_strategies = strategies
        end

        if defined?(::Freyja::CustomQueryContainer)
          strategies = ::Freyja::CustomQueryContainer.known_custom_queries_and_their_strategies
          strategies = strategies.merge(custom_query_strategies)
          ::Freyja::CustomQueryContainer.known_custom_queries_and_their_strategies = strategies
        end
      end
    end
  end
end
