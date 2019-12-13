# frozen_string_literal: true

module Bulkrax
  class ExporterRun < ApplicationRecord
    belongs_to :exporter
  end
end
