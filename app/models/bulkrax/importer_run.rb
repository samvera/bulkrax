# frozen_string_literal: true

module Bulkrax
  class ImporterRun < ApplicationRecord
    belongs_to :importer
  end
end
