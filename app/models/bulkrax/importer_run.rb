# frozen_string_literal: true

module Bulkrax
  class ImporterRun < ApplicationRecord
    belongs_to :importer
    has_many :statuses, as: :runnable, dependent: :destroy
    has_many :pending_relationships, dependent: :destroy

    def parents
      pending_relationships.pluck(:parent_id).uniq
    end

    delegate :user, to: :importer
  end
end
