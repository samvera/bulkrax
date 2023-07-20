# frozen_string_literal: true

class Bulkrax::InstallGenerator < Rails::Generators::Base
  source_root File.expand_path('../templates', __FILE__)

  desc 'This generator installs Bulkrax.'

  def banner
    say_status("info", "Generating Bulkrax installation", :blue)
  end

  def add_to_gemfile
    gem 'bulkrax'

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

  def create_bulkrax_api
    copy_file 'config/bulkrax_api.yml', 'config/bulkrax_api.yml'
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
    js = "\n// This line needs to be above the dataTables require in Hyku applications otherwise there will be jquery errors\n//= require bulkrax/application\n"

    return if file_text.include?(js)

    data_tables_rgx = /\/\/= require dataTables\/jquery.dataTables/
    require_tree_rgx = /\/\/= require_tree/

    if file_text.match?(data_tables_rgx)
      insert_into_file file, before: data_tables_rgx do
        "#{js}\n"
      end
    else
      insert_into_file file, before: require_tree_rgx do
        "#{js}\n"
      end
    end
  end

  def add_ability
    file = 'app/models/ability.rb'
    file_text = File.read(file)
    import_line = 'def can_import_works?'
    export_line = 'def can_export_works?'
    unless file_text.include?(import_line)
      insert_into_file file, before: /^end/ do
        "  def can_import_works?\n    can_create_any_work?\n  end"
      end
    end

    # rubocop:disable Style/GuardClause
    unless file_text.include?(export_line)
      insert_into_file file, before: /^end/ do
        "  def can_export_works?\n    can_create_any_work?\n  end"
      end
    end
    # rubocop:enable Style/GuardClause
  end

  def add_css
    ['css', 'scss', 'sass'].map do |ext|
      file = "app/assets/stylesheets/application.#{ext}"
      next unless File.exist?(file)

      file_text = File.read(file)
      css = "*= require 'bulkrax/application'"
      next if file_text.include?(css)

      insert_into_file file, before: /\s\*= require_self/ do
        "\s#{css}\n"
      end
    end
  end

  def display_readme
    readme 'README'
  end

  def add_removed_image
    copy_file 'app/assets/images/bulkrax/removed.png', 'app/assets/images/bulkrax/removed.png'
  end
end
