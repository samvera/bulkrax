# frozen_string_literal: true

namespace :bulkrax do
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
