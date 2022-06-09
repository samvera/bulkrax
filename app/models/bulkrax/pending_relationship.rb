# frozen_string_literal: true

module Bulkrax
  class PendingRelationship < ApplicationRecord
    belongs_to :importer_run
  end
end
