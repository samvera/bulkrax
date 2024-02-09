# frozen_string_literal: true

module Bulkrax
  class DeleteAndImportCollectionJob < DeleteAndImportJob
    self.delete_class = Bulkrax::DeleteCollectionJob
    self.import_class = Bulkrax::ImportCollectionJob
  end
end
