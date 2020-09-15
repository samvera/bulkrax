# frozen_string_literal: true

module Bulkrax
  class Status < ApplicationRecord
    belongs_to :statusable, polymorphic: true
    belongs_to :runnable, polymorphic: true
    serialize :error_backtrace, Array

    scope :for_importers, -> { where(statusable_type: 'Bulkrax::Importer') }
    scope :for_exporters, -> { where(statusable_type: 'Bulkrax::Exporter') }
  end
end
