# frozen_string_literal: true

module Bulkrax
  class ImportWorkCollectionJob < ApplicationJob
    queue_as :import

    def perform(*args)
      entry = Entry.find(args[0])
      begin
        entry.build
        entry.save
        ImporterRun.find(args[1]).increment!(:processed_collections)
      rescue => e
        ImporterRun.find(args[1]).increment!(:failed_collections)
        raise e
      end
    end
  end
end
