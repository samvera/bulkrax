# frozen_string_literal: true

module Bulkrax
  class DeleteFileSetJob < DeleteJob; end

  def perform(entry, importer_run)
    file_set = entry.factory.find
    if file_set
      parent = file_set.parent
      if parent && parent.respond_to?(:ordered_members)
        om = parent.ordered_members.to_a
        om.delete(file_set)
        parent.ordered_members = om
      elsif parent.respond_to?(:member_ids)
        parent.member_ids.delete(file_set.id)
        Hyrax.persister.save(resource: parent)
      end
      parent.save
    end

    super
  end

end
