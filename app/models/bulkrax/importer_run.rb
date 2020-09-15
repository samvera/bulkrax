# frozen_string_literal: true

module Bulkrax
  class ImporterRun < ApplicationRecord
    belongs_to :importer
    has_many :statuses, as: :runnable
  end
end
