# frozen_string_literal: true

module Bulkrax
  class ApplicationController < ::ApplicationController
    helper Rails.application.class.helpers
    protect_from_forgery with: :exception

    # Rescue CanCan::AccessDenied in all Bulkrax controllers.  HTML requests are
    # redirected to the host-app root with an alert; JSON requests receive a 403
    # response.  Defining the handler here (rather than in individual controllers)
    # keeps error handling in one place and consistent across all resources.
    rescue_from CanCan::AccessDenied do |exception|
      respond_to do |format|
        format.html do
          flash[:alert] = exception.message
          redirect_to main_app.root_path
        end
        format.json { render json: { error: exception.message }, status: :forbidden }
      end
    end

    protected

    # Single auth before_action for ImportersController and ExportersController.
    # Authenticates the request, then loads and authorizes the record targeted
    # by the current action, assigning it to @importer / @exporter (derived
    # from +klass+).
    #
    # * Authentication: API requests (see Bulkrax::API) use the token;
    #   everything else uses authenticate_user!.
    # * new/create: build a new record (from +<name>_params+ on create) and
    #   authorize it. Skipped for API requests, which validate params and build
    #   the record inside the action.
    # * Member actions: find by :id or :<name>_id (e.g. continue, download,
    #   entry_table) and authorize action_name. Custom actions resolve through
    #   the alias_action mappings in Bulkrax::Ability (e.g. :export_errors ->
    #   :read, :continue -> :update).
    # * Collection actions (no id param, e.g. index, *_table): nothing is
    #   loaded or authorized here; the action scopes with accessible_by.
    #
    # @param klass [Class] Bulkrax::Importer or Bulkrax::Exporter
    def authenticate_and_authorize!(klass)
      return unless authenticate_request!

      name = klass.model_name.element
      record = case action_name
               when 'new', 'create'
                 return if api_request?
                 klass.new(action_name == 'create' ? send(:"#{name}_params") : {})
               else
                 id = params[:id] || params[:"#{name}_id"]
                 return if id.blank?
                 klass.find(id)
               end
      instance_variable_set(:"@#{name}", record)

      # TODO(#1237): API requests have no current_user until the token is
      # resolved to a user, so API actions addressed by :id (and entry_table)
      # skip authorization to keep existing consumers working. Other
      # :<name>_id actions are authorized.
      return if api_request? && (params[:id].present? || action_name == 'entry_table')

      authorize! action_name.to_sym, record
    end

    private

    # Overridden by Bulkrax::API in controllers that accept token-authenticated
    # JSON requests.
    def api_request?
      false
    end

    # Returns false when authentication rendered or redirected, so the caller
    # can halt.
    def authenticate_request!
      api_request? ? token_authenticate! : authenticate_user!
      !performed?
    end
  end
end
