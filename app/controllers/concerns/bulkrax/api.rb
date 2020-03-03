# frozen_string_literal: true

module Bulkrax
  module API
    private

      def api_request?
        true if request.headers['Content-Type'] == 'application/json'
      end

      def token_authenticate!
        return true if request.headers['Authorization'] == "Token: #{ENV['BULKRAX_API_TOKEN']}"
        return json_response('invalid', :unauthorized, "Please supply the authorization token")
      end

      def json_response(method, status = :ok, message = nil)
        case method
        when 'index'
          render json: @importers, status: status
        when 'new', 'edit'
          render json: message, status: :method_not_allowed
        when 'destroy', 'invalid'
          render json: message, status: status
        else
          render json: message || @importer, status: status
        end
      end
  end
end
