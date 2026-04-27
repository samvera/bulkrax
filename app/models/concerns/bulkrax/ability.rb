# frozen_string_literal: true

module Bulkrax
  # Concern providing Bulkrax-specific ability methods.
  #
  # Include this in your application's Ability class to gain default
  # implementations of all Bulkrax authorization methods. Override any
  # method to customize authorization behavior for your application.
  #
  # ## Wiring CanCan rules
  #
  # Call +bulkrax_default_abilities+ from your Ability's +initialize+ (or add
  # it to +self.ability_logic+) to register CanCan +can+ rules for all
  # Bulkrax resources:
  #
  #   class Ability
  #     include Hydra::Ability
  #     include Bulkrax::Ability
  #     self.ability_logic += [:bulkrax_default_abilities]
  #   end
  #
  # The method uses the four predicate hooks below as guards, so you can
  # control who gets which rules simply by overriding those predicates.
  #
  # Example:
  #
  #   class Ability
  #     include Hydra::Ability
  #     include Bulkrax::Ability
  #     self.ability_logic += [:bulkrax_default_abilities]
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

    # Registers CanCan +can+ rules for all Bulkrax resources.
    #
    # Call this from your Ability's +initialize+ or add it to
    # +self.ability_logic+. The predicate hooks above control which rules are
    # granted; override them to tailor access.
    #
    # Rules for Importer and Exporter use hash-form conditions (SQL-generatable)
    # so they work with +Model.accessible_by(current_ability)+. Rules for Entry
    # use block-form conditions (checked in Ruby) because authorization must
    # traverse the parent association — do not call +Entry.accessible_by()+;
    # scope entries through the parent instead (e.g. +@importer.entries+).
    def bulkrax_default_abilities
      # Skip all rules when there is no authenticated user; avoids nil-id bugs
      # and prevents block rules from matching NULL user_id records.
      return unless current_user&.id

      # Map Bulkrax-specific non-CRUD actions to their closest CanCan equivalents
      # so that load_and_authorize_resource can authorize them without requiring
      # a dedicated `can` declaration for each custom action name.
      alias_action :entry_table, :importer_table, :exporter_table,
                   :original_file, :export_errors, :upload_corrected_entries,
                   :download, to: :read
      alias_action :continue, :upload_corrected_entries_file, to: :update

      if can_import_works?
        can :create, Bulkrax::Importer
        can [:read, :update, :destroy], Bulkrax::Importer, user_id: current_user.id
        can [:read, :update, :destroy], Bulkrax::Entry do |entry|
          entry.importerexporter.is_a?(Bulkrax::Importer) &&
            entry.importerexporter.user_id == current_user.id
        end
      end

      if can_export_works?
        can :create, Bulkrax::Exporter
        can [:read, :update, :destroy], Bulkrax::Exporter, user_id: current_user.id
        can [:read, :update, :destroy], Bulkrax::Entry do |entry|
          entry.importerexporter.is_a?(Bulkrax::Exporter) &&
            entry.importerexporter.user_id == current_user.id
        end
      end

      # Admin rules grant full management with no ownership restriction.
      can :manage, Bulkrax::Importer if can_admin_importers?
      can :manage, Bulkrax::Exporter if can_admin_exporters?
    end
  end
end
