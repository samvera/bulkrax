# frozen_string_literal: true

module Bulkrax
  class DeleteAndImportCollectionJob < DeleteAndImportJob
    DELETE_CLASS = Bulkrax::DeleteCollectionJob
    IMPORT_CLASS = Bulkrax::ImportCollectionJob
  end
end
