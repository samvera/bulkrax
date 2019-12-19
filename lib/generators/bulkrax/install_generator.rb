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

    hyrax = "\n# set bulkrax default work type to first curation_concern if it isn't already set\nif Bulkrax.default_work_type.blank?\n  Bulkrax.default_work_type = Hyrax.config.curation_concerns.first.to_s\nend\n"

    return if File.read('config/initializers/hyrax.rb').include?(hyrax)
    append_to_file 'config/initializers/hyrax.rb' do
      hyrax
    end
  end

  def create_api_definition
    copy_file 'config/api_definition.yml', 'config/api_definition.yml'
  end

  def create_cmd_script
    copy_file 'bin/importer', 'bin/importer'
  end

  def create_local_processing
    copy_file 'app/models/concerns/bulkrax/has_local_processing.rb', 'app/models/concerns/bulkrax/has_local_processing.rb'
  end

  def add_javascripts
    file = 'app/assets/javascripts/application.js'
    file_text = File.read(file)
    js = '//= require bulkrax/application'

    return if file_text.include?(js)
    insert_into_file file, before: /\/\/= require_tree ./ do
      "#{js}\n"
    end
  end

  def display_readme
    readme 'README'
  end
end
