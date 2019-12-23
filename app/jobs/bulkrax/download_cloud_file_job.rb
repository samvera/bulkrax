# frozen_string_literal: true

module Bulkrax
  class DownloadCloudFileJob < ApplicationJob
    queue_as :import

    # Retrieve cloud file and write to the imports directory
    # Note: if using the file system, the mounted directory in browse_everything MUST
    #   be shared by web and worker servers

    def perform(file, target_file)
      retriever = BrowseEverything::Retriever.new
      retriever.download(file, target_file) do |filename, retrieved, total|
        # The block is still useful for showing progress, but the
        # first argument is the filename instead of a chunk of data.
      end
    end
  end
end
