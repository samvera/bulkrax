# frozen_string_literal: true

module Bulkrax
  class ImportCollectionJob < ApplicationJob
    queue_as :import

    # rubocop:disable Rails/SkipsModelValidations
    def perform(*args)
      entry = Entry.find(args[0])
      begin
        entry.build
        entry.save
        add_user_to_permission_template!(entry) unless entry.importer.validate_only
        ImporterRun.find(args[1]).increment!(:processed_records)
        ImporterRun.find(args[1]).increment!(:processed_collections)
        ImporterRun.find(args[1]).decrement!(:enqueued_records)
      rescue => e
        ImporterRun.find(args[1]).increment!(:failed_records)
        ImporterRun.find(args[1]).increment!(:failed_collections)
        ImporterRun.find(args[1]).decrement!(:enqueued_records)
        raise e
      end
    end
    # rubocop:enable Rails/SkipsModelValidations

    private

    def add_user_to_permission_template!(entry)
      user                = ::User.find(entry.importerexporter.user_id)
      collection          = entry.factory.find
      permission_template = Hyrax::PermissionTemplate.find_or_create_by!(source_id: collection.id)

      Hyrax::PermissionTemplateAccess.find_or_create_by!(
        permission_template_id: permission_template.id,
        agent_id: user.user_key,
        agent_type: 'user',
        access: 'manage'
      )

      collection.reset_access_controls!
    end
  end
end
