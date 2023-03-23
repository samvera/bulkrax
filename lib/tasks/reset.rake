# frozen_string_literal: true

namespace :hyrax do
  namespace :reset do
    desc "Delete Bulkrax importers in addition to the reset below"
    task importers_et_all: :works_and_collections do
      # sometimes re-running an existing importer causes issues
      # and you may need to create new ones or delete the existing ones
      Bulkrax::Importer.delete_all
    end

    desc 'Reset fedora / solr and corresponding database tables w/o clearing other active record tables like users'
    task works_and_collections: [:environment] do
      confirm('You are about to delete all works and collections, this is not reversable!')
      require 'active_fedora/cleaner'
      Account.find_each do |account|
        Apartment::Tenant.switch!(account.tenant) if defined?(Apartment::Tenant)
        ActiveFedora::Cleaner.clean!
        Hyrax::PermissionTemplateAccess.delete_all
        Hyrax::PermissionTemplate.delete_all
        Bulkrax::PendingRelationship.delete_all
        Bulkrax::Entry.delete_all
        Bulkrax::ImporterRun.delete_all
        Bulkrax::Status.delete_all
        # Remove sipity methods, everything but sipity roles
        Sipity::Workflow.delete_all
        Sipity::EntitySpecificResponsibility.delete_all
        Sipity::Comment.delete_all
        Sipity::Entity.delete_all
        Sipity::WorkflowRole.delete_all
        Sipity::WorkflowResponsibility.delete_all
        Sipity::Agent.delete_all
        Mailboxer::Receipt.destroy_all
        Mailboxer::Notification.delete_all
        Mailboxer::Conversation::OptOut.delete_all
        Mailboxer::Conversation.delete_all
        # we need to wait till Fedora is done with its cleanup
        # otherwise creating the admin set will fail
        while AdminSet.exists?(AdminSet::DEFAULT_ID)
          puts 'waiting for delete to finish before reinitializing Fedora'
          sleep 20
        end

        Hyrax::CollectionType.find_or_create_default_collection_type
        Hyrax::CollectionType.find_or_create_admin_set_type
        AdminSet.find_or_create_default_admin_set_id

        collection_types = Hyrax::CollectionType.all
        collection_types.each do |c|
          next unless c.title.match?(/^translation missing/)
          oldtitle = c.title
          c.title = I18n.t(c.title.gsub("translation missing: en.", ''))
          c.save
          puts "#{oldtitle} changed to #{c.title}"
        end
      end
    end

    def confirm(action)
      return if ENV['RESET_CONFIRMED'].present?
      confirm_token = rand(36**6).to_s(36)
      STDOUT.puts "#{action} Enter '#{confirm_token}' to confirm:"
      input = STDIN.gets.chomp
      raise "Aborting. You entered #{input}" unless input == confirm_token
    end
  end
end
