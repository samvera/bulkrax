# frozen_string_literal: true

module Bulkrax
  class ExporterRun < ApplicationRecord
    include EnqueuedRecordsCounter

    belongs_to :exporter
  end
end
