# frozen_string_literal: true

module Bulkrax
  class DeleteFileSetJob < DeleteJob; end

  def perform(entry, importer_run)
    file_set = entry.factory.find
    if file_set
      parent = file_set.parent
      om = parent.ordered_members.to_a
      om.delete(file_set)
      parent.ordered_members = om
      parent.save
    end

    super
  end

end
