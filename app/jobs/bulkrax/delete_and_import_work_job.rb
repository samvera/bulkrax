# frozen_string_literal: true

module Bulkrax
  class DeleteAndImportWorkJob < DeleteAndImportJob
    DELETE_CLASS = Bulkrax::DeleteWorkJob
    IMPORT_CLASS = Bulkrax::ImportWorkJob
  end
end
