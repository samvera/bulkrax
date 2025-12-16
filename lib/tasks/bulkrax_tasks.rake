# frozen_string_literal: true
require 'ruby-progressbar'

namespace :bulkrax do
  desc 'Update all status messages from the latest status. This is to refresh the denormalized field'
  task update_status_messages: :environment do
    @progress = ProgressBar.create(total: Bulkrax::Status.latest_by_statusable.count,
                                   format: "%a %b\u{15E7}%i %c/%C %p%% %t",
                                   progress_mark: ' ',
                                   remainder_mark: "\u{FF65}")
    Bulkrax::Status.latest_by_statusable.includes(:statusable).find_each do |status|
      status.statusable.update(status_message: status.status_message, error_class: status.error_class)
      @progress.increment
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
    Bulkrax::Exporter.find_each { |e| Bulkrax::ExporterJob.perform_later(e.id) }
  rescue => e
    puts "(#{e.message})"
  end

  desc "Resave importers"
  task resave_importers: :environment do
    if defined?(::Hyku)
      Account.find_each do |account|
        next if account.name == "search"
        switch!(account)
        puts "=============== updating #{account.name} ============"

        resave_importers

        puts "=============== finished updating #{account.name} ============"
      end
    else
      resave_importers
    end
  end

  def resave_importers
    Bulkrax::Importer.find_each(&:save!)
  end
end
