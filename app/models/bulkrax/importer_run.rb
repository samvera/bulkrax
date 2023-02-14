# frozen_string_literal: true

module Bulkrax
  class ImporterRun < ApplicationRecord
    belongs_to :importer
    has_many :statuses, as: :runnable, dependent: :destroy
    has_many :pending_relationships, dependent: :destroy

    def parents
      pending_relationships.pluck(:parent_id).uniq
    end

    def user
      # An importer might not have a user, the CLI ingest need not assign a user.  As such, we
      # fallback to the configured user.
      importer.user || Bulkrax.fallback_user_for_importer_exporter_processing
    end
  end
end
