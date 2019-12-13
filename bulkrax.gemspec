# frozen_string_literal: true

$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "bulkrax/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "bulkrax"
  s.version     = Bulkrax::VERSION
  s.authors     = ["Rob Kaufman"]
  s.email       = ["rob@notch8.com"]
  s.homepage    = "https://github.com/samvera-labs/bulkrax"
  s.summary     = "Summary of Bulkrax."
  s.description = "Description of Bulkrax."
  s.license     = "Apache-2.0"

  s.files = Dir["{app,config,db,lib}/**/*", "LICENSE", "Rakefile", "README.md"]

  s.add_dependency "rails", ">= 5.1.6"
  s.add_dependency "loofah", ">= 2.2.3" # security issue, remove on rails upgrade
  s.add_dependency "rack", ">= 2.0.6" # security issue, remove on rails upgrade
  s.add_dependency "simple_form"
  s.add_dependency 'iso8601', '~> 0.9.0'
  s.add_dependency 'oai', '~> 0.4'
  s.add_dependency 'libxml-ruby', '~> 3.1.0'
  s.add_dependency 'language_list', '~> 1.2', '>= 1.2.1'
  s.add_dependency 'rdf', '>= 2.0.2', '< 4.0'
  s.add_dependency 'bagit', '~> 0.4'

  s.add_development_dependency 'sqlite3', '~> 1.3.13'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'bixby'
end
