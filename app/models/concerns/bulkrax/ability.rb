# frozen_string_literal: true

module Bulkrax
  # Concern providing Bulkrax-specific ability methods.
  #
  # Include this in your application's Ability class to gain default
  # implementations of all Bulkrax authorization methods. Override any
  # method to customize authorization behavior for your application.
  #
  # Example:
  #
  #   class Ability
  #     include Hydra::Ability
  #     include Bulkrax::Ability
  #
  #     # Grant import/export access to users who can create works
  #     def can_import_works?
  #       can_create_any_work?
  #     end
  #
  #     def can_export_works?
  #       can_create_any_work?
  #     end
  #
  #     # Grant admin-level importer access to site admins
  #     def can_admin_importers?
  #       current_user.admin?
  #     end
  #   end
  module Ability
    extend ActiveSupport::Concern

    # Returns true if the current user may use importer functionality at all.
    # Override in your Ability class to customize.
    def can_import_works?
      false
    end

    # Returns true if the current user may use exporter functionality at all.
    # Override in your Ability class to customize.
    def can_export_works?
      false
    end

    # Returns true if the current user may administer ALL importers —
    # i.e., view, edit, update, or destroy any importer regardless of ownership.
    # Defaults to false; override to grant admin access.
    def can_admin_importers?
      false
    end

    # Returns true if the current user may administer ALL exporters —
    # i.e., view, edit, update, or destroy any exporter regardless of ownership.
    # Defaults to false; override to grant admin access.
    def can_admin_exporters?
      false
    end
  end
end
