# frozen_string_literal: true

source 'https://rubygems.org'

# Declare your gem's dependencies in bulkrax.gemspec.
# Bundler will treat runtime dependencies like base dependencies, and
# development dependencies will be added by default to the :development group.
gemspec

# Declare any dependencies that are still in development here instead of in
# your gemspec. These might include edge Rails or gems from your path or
# Git. Remember to move these dependencies to your gemspec before releasing
# your gem to rubygems.org.

gem 'blacklight', '~> 6.20.0'
gem 'bootstrap-sass', '~> 3.0'
gem 'coderay'
gem 'factory_bot_rails'
gem 'hyrax', '>= 2.3'
gem 'oai'
gem 'rsolr', '>= 1.0'
gem 'rspec-rails'
gem 'twitter-typeahead-rails', '0.11.1.pre.corejavascript'

group :development, :test do
  # To use a debugger
  gem 'byebug'
  gem 'database_cleaner'
  gem 'pry-byebug'
  gem 'solr_wrapper', '>= 0.3'
end

group :lint do
  gem 'bixby'
end
