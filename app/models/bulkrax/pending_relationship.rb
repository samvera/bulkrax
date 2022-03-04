module Bulkrax
  class PendingRelationship < ApplicationRecord
    belongs_to :bulkrax_importer_run
  end
end
