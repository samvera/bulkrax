# frozen_string_literal: true

module Bulkrax
  class DeleteAndImportWorkJob < DeleteAndImportJob
    self.delete_class = Bulkrax::DeleteWorkJob
    self.import_class = Bulkrax::ImportWorkJob
  end
end
