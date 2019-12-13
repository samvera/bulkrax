# frozen_string_literal: true

module Bulkrax
  class ExporterJob < ApplicationJob
    queue_as :export

    def perform(exporter_id)
      exporter = Exporter.find(exporter_id)
      exporter.export
      exporter.write
    end
  end
end
