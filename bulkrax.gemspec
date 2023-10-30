# frozen_string_literal: true

$LOAD_PATH.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "bulkrax/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "bulkrax"
  s.version     = Bulkrax::VERSION
  s.authors     = ["Rob Kaufman"]
  s.email       = ["rob@notch8.com"]
  s.homepage    = "https://github.com/samvera-labs/bulkrax"
  s.summary     = "Import and export tool for Hyrax and Hyku"
  s.description = "Bulkrax is a batteries included importer for Samvera applications. It currently includes support for OAI-PMH (DC and Qualified DC) and CSV out of the box. It is also designed to be extensible, allowing you to easily add new importers in to your application or to include them with other gems. Bulkrax provides a full admin interface including creating, editing, scheduling and reviewing imports."
  s.license     = "Apache-2.0"

  s.files = Dir["{app,config,db,lib}/**/*", "LICENSE", "Rakefile", "README.md"]

  s.add_dependency 'rails', '>= 5.1.6'
  s.add_dependency 'bagit', '~> 0.4'
  s.add_dependency 'coderay'
  s.add_dependency 'dry-monads', '~> 1.5.0'
  s.add_dependency 'iso8601', '~> 0.9.0'
  s.add_dependency 'kaminari'
  s.add_dependency 'language_list', '~> 1.2', '>= 1.2.1'
  s.add_dependency 'libxml-ruby', '~> 3.2.4'
  s.add_dependency 'loofah', '>= 2.2.3' # security issue, remove on rails upgrade
  s.add_dependency 'oai', '>= 0.4', '< 2.x'
  s.add_dependency 'rack', '>= 2.0.6' # security issue, remove on rails upgrade
  s.add_dependency 'rdf', '>= 2.0.2', '< 4.0'
  s.add_dependency 'rubyzip'
  s.add_dependency 'simple_form'

  s.add_development_dependency 'sqlite3', '~> 1.3.13'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'redis', '~> 4.2'
  s.add_development_dependency 'psych', '~> 3.3'
end
