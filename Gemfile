# frozen_string_literal: true

source 'https://rubygems.org'

# Declare your gem's dependencies in bulkrax.gemspec.
# Bundler will treat runtime dependencies like base dependencies, and
# development dependencies will be added by default to the :development group.
# Install gems from test app
if ENV['RAILS_ROOT']
  test_app_gemfile_path = File.expand_path('Gemfile', ENV['RAILS_ROOT'])
  eval_gemfile test_app_gemfile_path
else
  gemspec
end

# Declare any dependencies that are still in development here instead of in
# your gemspec. These might include edge Rails or gems from your path or
# Git. Remember to move these dependencies to your gemspec before releasing
# your gem to rubygems.org.

gem 'blacklight'
gem 'bootstrap-sass', '~> 3.4.1'
gem 'coderay'
gem 'concurrent-ruby', '1.3.4'
gem 'factory_bot_rails' unless ENV['CI']

# Bulkrax supports Hyrax 2.3 through 5.2 only.
gem 'hyrax', ENV['HYRAX_VERSION'] || '~> 5.0' unless ENV['CI']

gem 'oai'
gem 'pg' unless ENV['CI']
gem 'rails', ENV['RAILS_GEM_VERSION'] || '~> 7.2' unless ENV['CI']
gem 'rsolr', '>= 1.0' unless ENV['CI']
gem 'twitter-typeahead-rails', '0.11.1.pre.corejavascript'

group :development, :test do
  # To use a debugger
  gem 'byebug'
  gem 'database_cleaner'
  gem 'pry-byebug'
  gem 'rspec-rails'
  gem 'solargraph'
  gem 'solr_wrapper', '>= 0.3'
  gem 'sqlite3', '~> 1.4'
end

group :test do
  gem 'rails-controller-testing'
  gem 'simplecov'
  gem 'webmock'
end

group :lint do
  gem 'bixby' unless ENV['CI']
  gem 'rubocop-factory_bot', require: false unless ENV['CI']
end
