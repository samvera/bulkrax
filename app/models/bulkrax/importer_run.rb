# frozen_string_literal: true

module Bulkrax
  class ImporterRun < ApplicationRecord
    belongs_to :importer
    has_many :statuses, as: :runnable, dependent: :destroy

    serialize :parents, Array
  end
end
