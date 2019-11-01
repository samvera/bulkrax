# frozen_string_literal: true

class Bulkrax::InstallGenerator < Rails::Generators::Base
  source_root File.expand_path('../templates', __FILE__)

  desc 'This generator installs Bulkrax.'

  def banner
    say_status("info", "Generating Bulkrax installation", :blue)
  end

  def add_to_gemfile
    gem 'willow_sword', github: 'notch8/willow_sword'

    Bundler.with_clean_env do
      run "bundle install"
    end
  end

  def mount_route
    route "mount Bulkrax::Engine, at: '/'"
  end

  def create_config
    copy_file 'config/initializers/bulkrax.rb', 'config/initializers/bulkrax.rb'
  end

  def create_local_processing
    copy_file 'app/models/bulkrax/concerns/has_local_processing.rb', 'app/models/bulkrax/concerns/has_local_processing.rb'
  end

  def add_javascripts
    file = 'app/assets/javascripts/application.js'
    file_text = File.read(file)
    js = '//= require bulkrax/application'

    insert_into_file file, before: /\/\/= require_tree ./ do
      "#{js}\n"
    end unless file_text.include?(js)
  end

  def display_readme
    readme 'README'
  end
end
