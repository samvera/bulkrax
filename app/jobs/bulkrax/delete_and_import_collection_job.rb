# frozen_string_literal: true

module Bulkrax
  class DeleteAndImportCollectionJob < DeleteAndImportJob
    self.delete_job = Bulkrax::DeleteCollectionJob
    self.import_job = Bulkrax::ImportCollectionJob
  end
end
