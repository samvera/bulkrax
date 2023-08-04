# frozen_string_literal: true

namespace :bulkrax do
  # Usage example: rails bulkrax:generate_test_csvs['5','100','GenericWork']
  desc 'Generate CSVs with fake data for testing purposes'
  task :generate_test_csvs, [:num_of_csvs, :csv_rows, :record_type] => :environment do |_t, args|
    # NOTE: If this line throws an error, run `gem install faker` inside your Docker container
    require 'faker'
    require 'csv'

    FileUtils.mkdir_p(Rails.root.join('tmp', 'imports'))

    IGNORED_PROPERTIES = %w[
      admin_set_id
      alternate_ids
      arkivo_checksum
      created_at
      date_modified
      date_uploaded
      depositor
      embargo
      has_model
      head
      internal_resource
      label
      lease
      member_ids
      member_of_collection_ids
      modified_date
      new_record
      on_behalf_of
      owner
      proxy_depositor
      rendering_ids
      representative_id
      state
      tail
      thumbnail_id
      updated_at
    ].freeze

    BULKRAX_PROPERTIES = %w[
      source_identifier
      model
    ].freeze

    num_of_csvs = args.num_of_csvs.presence&.to_i || 5
    csv_rows = args.csv_rows.presence&.to_i || 100
    record_type = args.record_type.presence&.constantize || GenericWork

    csv_header = if Hyrax.config.try(:use_valkyrie?)
                   record_type.schema.map { |k| k.name.to_s }
                 else
                   record_type.properties.keys
                 end

    csv_header -= IGNORED_PROPERTIES
    csv_header.unshift(*BULKRAX_PROPERTIES)

    num_of_csvs.times do |i|
      CSV.open(Rails.root.join('tmp', 'imports', "importer_#{i}.csv"), 'wb') do |csv|
        csv << csv_header
        csv_rows.times do |_index|
          row = []
          csv_header.each do |prop_name|
            row << case prop_name
                   when 'id', 'source_identifier'
                     Faker::Number.number(digits: 4)
                   when 'model'
                     record_type.to_s
                   when 'rights_statement'
                     'http://rightsstatements.org/vocab/CNE/1.0/'
                   when 'license'
                     'https://creativecommons.org/licenses/by-nc/4.0/'
                   when 'based_near'
                     # FIXME: Set a proper :based_near value
                     nil
                   else
                     Faker::Lorem.sentence
                   end
          end
          csv << row
        end
      end
    end

    num_of_csvs.times do |i|
      Bulkrax::Importer.create(
        name: "Generated CSV #{i}",
        admin_set_id: 'admin_set/default',
        user_id: User.find_by(email: 'admin@example.com').id,
        frequency: 'PT0S',
        parser_klass: 'Bulkrax::CsvParser',
        parser_fields: {
          'visibility' => 'open',
          'rights_statement' => '',
          'override_rights_statement' => '0',
          'file_style' => 'Specify a Path on the Server',
          'import_file_path' => "tmp/imports/importer_#{i}.csv",
          'update_files' => false
        }
      )
    end
  end

  desc "Remove old exported zips and create new ones with the new file structure"
  task rerun_all_exporters: :environment do
    # delete the existing folders and zip files
    Dir["tmp/exports/**"].each { |file| FileUtils.rm_rf(file) }

    if defined?(::Hyku)
      Account.find_each do |account|
        next if account.name == "search"
        switch!(account)
        puts "=============== updating #{account.name} ============"

        make_new_exports

        puts "=============== finished updating #{account.name} ============"
      end
    else
      make_new_exports
    end
  end

  def make_new_exports
    Bulkrax::Exporter.all.each { |e| Bulkrax::ExporterJob.perform_later(e.id) }
  rescue => e
    puts "(#{e.message})"
  end
end
