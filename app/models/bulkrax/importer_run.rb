module Bulkrax
  class ImporterRun < ApplicationRecord
    belongs_to :importer, foreign_key: 'bulkrax_importer_id'
  end
end
