# frozen_string_literal: true

module Bulkrax
  class DeleteAndImportFileSetJob < DeleteAndImportJob
    DELETE_CLASS = Bulkrax::DeleteFileSetJob
    IMPORT_CLASS = Bulkrax::ImportFileSetJob
  end
end
