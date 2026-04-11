# frozen_string_literal: true

module Bulkrax
  class ApplicationController < ::ApplicationController
    helper Rails.application.class.helpers
    protect_from_forgery with: :exception

    private

    # Returns a relation of Importer records the current user may access.
    # Importer admins see all importers; other users see only their own.
    def accessible_importers
      if current_ability.can_admin_importers?
        Importer.all
      else
        Importer.where(user_id: current_user&.id)
      end
    end

    # Returns a relation of Exporter records the current user may access.
    # Exporter admins see all exporters; other users see only their own.
    def accessible_exporters
      if current_ability.can_admin_exporters?
        Exporter.all
      else
        Exporter.where(user_id: current_user&.id)
      end
    end

    # Returns true if the given importer or exporter is accessible to the current user.
    def item_accessible?(item)
      case item
      when Importer
        accessible_importers.exists?(item.id)
      when Exporter
        accessible_exporters.exists?(item.id)
      else
        false
      end
    end
  end
end
