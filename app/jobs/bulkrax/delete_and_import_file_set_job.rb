# frozen_string_literal: true

module Bulkrax
  class DeleteAndImportFileSetJob < DeleteAndImportJob
    self.delete_class = Bulkrax::DeleteFileSetJob
    self.import_class = Bulkrax::ImportFileSetJob
  end
end
