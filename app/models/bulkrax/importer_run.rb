# frozen_string_literal: true

module Bulkrax
  class ImporterRun < ApplicationRecord
    belongs_to :importer
    has_many :statuses, as: :runnable, dependent: :destroy

    def parents
      PendingRelationship.where(bulkrax_importer_run_id: id).pluck(:parent_id).uniq
    end
  end
end
