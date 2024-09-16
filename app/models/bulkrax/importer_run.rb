# frozen_string_literal: true

module Bulkrax
  class ImporterRun < ApplicationRecord
    belongs_to :importer
    has_many :statuses, as: :runnable, dependent: :destroy
    has_many :pending_relationships, dependent: :destroy

    after_save :set_last_imported_at
    after_save :set_next_import_at

    def parents
      pending_relationships.pluck(:parent_id).uniq
    end

    def user
      # An importer might not have a user, the CLI ingest need not assign a user.  As such, we
      # fallback to the configured user.
      importer.user || Bulkrax.fallback_user_for_importer_exporter_processing
    end

    def set_last_imported_at
      importer.update(last_imported_at: importer.last_imported_at)
    end

    def set_next_import_at
      importer.update(next_import_at: importer.next_import_at)
    end
  end
end
