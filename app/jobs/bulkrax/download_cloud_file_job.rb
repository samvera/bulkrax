# frozen_string_literal: true
module Bulkrax
  class DownloadCloudFileJob < ApplicationJob
    queue_as Bulkrax.config.ingest_queue_name

    include ActionView::Helpers::NumberHelper

    # Retrieve cloud file and write to the imports directory
    # Note: if using the file system, the mounted directory in
    #   browse_everything MUST be shared by web and worker servers
    def perform(file, target_file)
      retriever = BrowseEverything::Retriever.new
      last_logged_time = Time.zone.now
      log_interval = 3.seconds

      retriever.download(file, target_file) do |filename, retrieved, total|
        percentage = (retrieved.to_f / total.to_f) * 100
        current_time = Time.zone.now

        if (current_time - last_logged_time) >= log_interval
          # Use number_to_human_size for formatting
          readable_retrieved = number_to_human_size(retrieved)
          readable_total = number_to_human_size(total)
          Rails.logger.info "Downloaded #{readable_retrieved} of #{readable_total}, #{filename}: #{percentage.round}% complete"
          last_logged_time = current_time
        end
      end
      Rails.logger.info "Download complete: #{file['url']} to #{target_file}"
    end
  end
end
