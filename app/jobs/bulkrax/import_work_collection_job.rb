# frozen_string_literal: true

module Bulkrax
  class ImportWorkCollectionJob < ApplicationJob
    queue_as :import

    # rubocop:disable Rails/SkipsModelValidations
    def perform(*args)
      entry = Entry.find(args[0])
      begin
        entry.build
        entry.save
        add_user_to_permission_template!(entry)
        ImporterRun.find(args[1]).increment!(:processed_collections)
        ImporterRun.find(args[1]).decrement!(:enqueued_records)
      rescue => e
        ImporterRun.find(args[1]).increment!(:failed_collections)
        ImporterRun.find(args[1]).decrement!(:enqueued_records)
        raise e
      end
    end
    # rubocop:enable Rails/SkipsModelValidations

    def add_user_to_permission_template!(entry)
      user                = ::User.find(entry.importerexporter.user_id)
      collection          = entry.factory.find
      permission_template = Hyrax::PermissionTemplate.find_by(source_id: collection.id)

      if permission_template.present?
        Hyrax::PermissionTemplateAccess.create!(
          permission_template_id: permission_template.id,
          agent_id: user.email,
          agent_type: 'user',
          access: 'manage'
        )
      else
        Hyrax::PermissionTemplate.create!(source_id: collection.id, manage_users: [user])
      end
    end
  end
end
