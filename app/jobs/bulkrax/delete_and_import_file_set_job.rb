# frozen_string_literal: true

module Bulkrax
  class DeleteAndImportFileSetJob < DeleteAndImportJob
    self.delete_job = Bulkrax::DeleteFileSetJob
    self.import_job = Bulkrax::ImportFileSetJob
  end
end
