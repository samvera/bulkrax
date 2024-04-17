# frozen_string_literal: true

# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
require 'bulkrax/entry_spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require 'simplecov'
SimpleCov.start
require File.expand_path("../test_app/config/environment", __FILE__)
ENGINE_RAILS_ROOT = File.join(File.dirname(__FILE__), '../')
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'
# Add additional requires below this line. Rails is not loaded until this point!

FactoryBot.definition_file_paths << File.join(File.dirname(__FILE__), 'factories')
FactoryBot.find_definitions

Bulkrax.default_work_type = 'Work'

# In Bulkrax 7+ we introduced a new object factory.  And we've been moving code
# into that construct; namely code that involves the types of object's we're
# working with.
Bulkrax.object_factory = Bulkrax::ObjectFactory

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.
#
Dir["./spec/support/**/*.rb"].sort.each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  puts e.to_s.strip
  exit 1
end
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods

  config.before(:suite) do
    DatabaseCleaner.clean_with :truncation
    DatabaseCleaner.strategy = :transaction
  end

  config.before do
    DatabaseCleaner.start
  end

  config.after do
    DatabaseCleaner.clean
  rescue
    puts 'database clean failed'
  end

  config.after(:each, clean_downloads: true) do
    FileUtils.rm_rf(Dir.glob("#{ENV.fetch('RAILS_TMP', Dir.tmpdir)}/*_entries.csv"))
    # Account for single tenant and multi tenant files
    # 'hyku' should be the only tenant referred to in the specs
    FileUtils.rm_rf(Dir.glob(File.join(Bulkrax.import_path, '1', '/*_entries.csv').to_s))
    FileUtils.rm_rf(Dir.glob(File.join(Bulkrax.import_path, 'hyku', '1', '1', '/*.csv').to_s))
    FileUtils.rm_rf(Dir.glob(File.join(Bulkrax.export_path, '1', '/*_entries.csv').to_s))
    FileUtils.rm_rf(Dir.glob(File.join(Bulkrax.export_path, 'hyku', '1', '1', '/*.csv').to_s))
  end

  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_path = Rails.root.join('spec', 'fixtures')

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  #
  # You can disable this behaviour by removing the line below, and instead
  # explicitly tag your specs with their type, e.g.:
  #
  #     RSpec.describe UsersController, :type => :controller do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://relishapp.com/rspec/rspec-rails/docs
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")
end
