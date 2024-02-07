# frozen_string_literal: true

module Bulkrax
  module ValidationHelper
    def valid_create_params?
      check_admin_set
      check_user
      return true if valid_importer? && valid_commit? &&
                     valid_name? && valid_parser_klass? &&
                     valid_parser_fields?
    end

    def valid_update_params?
      check_admin_set
      check_user
      return valid_commit?
    end

    def check_admin_set
      return unless defined?(::Hyrax)

      if params[:importer][:admin_set_id].blank?
        params[:importer][:admin_set_id] = AdminSet::DEFAULT_ID
      else
        AdminSet.find(params[:importer][:admin_set_id])
      end
      return true
    rescue ActiveFedora::ObjectNotFoundError, Bulkrax::ObjectFactoryInterface::ObjectNotFoundError
      logger.warn("AdminSet #{params[:importer][:admin_set_id]} not found. Using default admin set.")
      params[:importer][:admin_set_id] = AdminSet::DEFAULT_ID
      return true
    end

    def check_user
      if params[:importer][:user_id].blank?
        params[:importer][:user_id] = User.batch_user.id
      else
        User.find(params[:importer][:user_id])
      end
      return true
    rescue ActiveRecord::RecordNotFound
      logger.warn("User #{params[:importer][:user_id]} not found. Using default batch_user.")
      params[:importer][:user_id] = User.batch_user.id
      return true
    end

    def return_value(method, status, message)
      @return_value ||= [method, status, message]
    end

    def return_json_response
      json_response(@return_value[0], @return_value[1], @return_value[2])
    end

    def valid_importer?
      return true if params[:importer].present?
      return_value('invalid',
                   :unprocessable_entity,
                   "Missing required parameters")
      return false
    end

    def valid_commit?
      return true if params[:commit].present? && valid_commit_message?(params[:commit])
      return_value('invalid',
                   :unprocessable_entity,
                   "[:commit] is required")
      return false
    end

    def valid_name?
      return true if params[:importer][:name].present?
      return_value('invalid',
                   :unprocessable_entity,
                   "[:importer][:name] is required")
      return false
    end

    def valid_parser_klass?
      return true if params[:importer][:parser_klass].present?
      return_value('invalid',
                   :unprocessable_entity,
                   "[:importer][:parser_klass] is required")
      return false
    end

    def valid_parser_fields?
      if params[:importer][:parser_fields].present?
        case params[:importer][:parser_klass]
        when 'Bulkrax::OaiParser'
          return valid_oai?
        when 'Bulkrax::CsvParser'
          return valid_csv?
        when 'Bulkrax::BagitParser'
          return valid_bagit?
        else
          return_value('invalid',
                       :unprocessable_entity,
                       "#{params[:importer][:parser_klass]} not recognised")
          return false
        end
      else
        return_value('invalid',
                     :unprocessable_entity,
                     "params[:importer][:parser_fields] is required")
        return false
      end
    end

    def valid_bagit?
      return true if params[:importer][:parser_fields][:metadata_format].present? &&
                     params[:importer][:parser_fields][:metadata_file_name].present? &&
                     params[:importer][:parser_fields][:import_file_path].present?
      return_value('invalid',
                   :unprocessable_entity,
                   "[:importer][:parser_fields] [:metadata_format], [:metadata_file_name] and [:import_file_path] are required")
      return false
    end

    def valid_csv?
      return true if params[:importer][:parser_fields][:import_file_path].present?
      return_value('invalid',
                   :unprocessable_entity,
                   "[:importer][:parser_fields] [:import_file_path] is required")
      return false
    end

    def valid_oai?
      return true if params[:base_url].present? &&
                     params[:importer][:parser_fields][:set].present? &&
                     params[:importer][:parser_fields][:collection_name].present?
      return_value('invalid',
                   :unprocessable_entity,
                   "[:base_url], [:importer][:parser_fields][:set] and [:importer][:parser_fields][:collection_name] are required")
      return false
    end

    def valid_commit_message?(commit)
      # @todo - manual list because this line causes the importer script to fail - why?
      # Bulkrax.api_definition['bulkrax']['importer']['commit']['valid_values'].include?(commit)
      [
        "Create",
        "Create and Import",
        "Update Importer",
        "Update and Re-Import (update metadata and replace files)",
        "Update and Harvest Updated Items",
        "Update and Re-Harvest All Items",
        "Update and Re-Import (update metadata only)",
        "Update and Import (importer has not yet been run)"
      ].include?(commit)
    end
  end
end
