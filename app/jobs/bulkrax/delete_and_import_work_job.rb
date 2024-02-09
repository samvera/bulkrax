# frozen_string_literal: true

module Bulkrax
  class DeleteAndImportWorkJob < DeleteAndImportJob
    self.delete_job = Bulkrax::DeleteWorkJob
    self.import_job = Bulkrax::ImportWorkJob
  end
end
