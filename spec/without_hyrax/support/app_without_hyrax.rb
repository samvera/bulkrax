# frozen_string_literal: true

require 'tempfile'
require 'tmpdir'
require_relative '../../rails_compat_app/config/environment'

RSpec.shared_context 'a Bulkrax app without Hyrax' do
  before(:all) do
    ActiveRecord::Migration.verbose = false
    paths = Bulkrax::Engine.paths['db/migrate'].expanded + [Rails.root.join('db', 'migrate').to_s]
    migrations = ActiveRecord::MigrationContext.new(paths)
    # Resetting again would drop the accessors Work defines when it loads.
    next unless migrations.needs_migration?

    migrations.migrate
    ActiveRecord::Base.descendants.each(&:reset_column_information)
  end

  around do |example|
    previous_entry_work_type = Bulkrax::CsvEntry.default_work_type
    previous_adapter = ActiveJob::Base.queue_adapter
    export_path = Dir.mktmpdir
    settings = {
      object_factory: NonHyraxFactory,
      default_work_type: 'Work',
      curation_concerns: [Work],
      file_model_class: Attachment,
      export_path: export_path,
      field_mappings: {
        'Bulkrax::CsvParser' => {
          'bulkrax_identifier' => { from: ['bulkrax_identifier'], source_identifier: true },
          'title' => { from: ['title'] },
          'creator' => { from: ['creator'], split: true },
          'parents' => { from: ['parents'], related_parents_field_mapping: true, split: true }
        }
      }
    }
    previous = settings.keys.index_with { |key| Bulkrax.config.public_send(key) }
    settings.each { |key, value| Bulkrax.config.public_send("#{key}=", value) }
    # Entries read the default work type when their class loads, so an app
    # configuring Bulkrax after that sets it on the entry class as well.
    Bulkrax::CsvEntry.default_work_type = 'Work'
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = true
    ActiveJob::Base.queue_adapter.perform_enqueued_at_jobs = true
    example.run
  ensure
    previous&.each { |key, value| Bulkrax.config.public_send("#{key}=", value) }
    Bulkrax::CsvEntry.default_work_type = previous_entry_work_type
    ActiveJob::Base.queue_adapter = previous_adapter
    [Work, Bulkrax::PendingRelationship, Bulkrax::Status, Bulkrax::Entry, Bulkrax::ImporterRun, Bulkrax::Importer,
     Bulkrax::ExporterRun, Bulkrax::Exporter, User].each(&:delete_all)
    FileUtils.remove_entry(export_path) if export_path
  end

  let(:user) { User.create!(email: 'importer@example.com') }

  def import(csv)
    file = Tempfile.new(['import', '.csv'])
    file.write(csv)
    file.close
    importer = Bulkrax::Importer.create!(name: 'CSV import', user: user, admin_set_id: nil, frequency: 'PT0S',
                                         parser_klass: 'Bulkrax::CsvParser',
                                         field_mapping: Bulkrax.field_mappings['Bulkrax::CsvParser'],
                                         parser_fields: { 'import_file_path' => file.path })
    Bulkrax::ImporterJob.perform_now(importer.id)
    importer.reload
  end
end
