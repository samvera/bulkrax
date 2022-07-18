# frozen_string_literal: true

namespace :bulkrax do
  desc "Remove old exported zips and create new ones with the new file structure"
  task rerun_all_exporters: :environment do
    if defined?(::Hyku)
      Account.find_each do |account|
        puts "=============== updating #{account.name} ============"
        next if account.name == "search"
        switch!(account)

        rerun_exporters_and_delete_zips

        puts "=============== finished updating #{account.name} ============"
      end
    else
      rerun_exporters_and_delete_zips
    end
  end

  def rerun_exporters_and_delete_zips
    begin
      Bulkrax::Exporter.all.each { |e| Bulkrax::ExporterJob.perform_later(e.id) }
    rescue => e
      puts "(#{e.message})"
    end

    Dir["tmp/exports/**.zip"].each { |zip_path| FileUtils.rm_rf(zip_path) }
  end
end
