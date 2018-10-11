$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "bulkrax/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "bulkrax"
  s.version     = Bulkrax::VERSION
  s.authors     = ["Rob Kaufman"]
  s.email       = ["rob@notch8.com"]
  s.homepage    = "TODO"
  s.summary     = "TODO: Summary of Bulkrax."
  s.description = "TODO: Description of Bulkrax."
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  s.add_dependency "rails", "~> 5.1.6"

  s.add_development_dependency "sqlite3"
end
