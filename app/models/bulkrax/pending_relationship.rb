# frozen_string_literal: true

module Bulkrax
  class PendingRelationship < ApplicationRecord
    belongs_to :bulkrax_importer_run, class_name: "::Bulkrax::ImporterRun"
  end
end
