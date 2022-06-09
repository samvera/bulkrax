# frozen_string_literal: true

module Bulkrax
  # Import Behavior for Entry classes
  module ImportBehavior # rubocop:disable Metrics/ModuleLength
    extend ActiveSupport::Concern

    def build_for_importer
      begin
        build_metadata
        unless self.importerexporter.validate_only
          raise CollectionsCreatedError unless collections_created?
          @item = factory.run!
          add_user_to_permission_templates! if self.class.to_s.include?("Collection")
          parent_jobs if self.parsed_metadata[related_parents_parsed_mapping].present?
          child_jobs if self.parsed_metadata[related_children_parsed_mapping].present?
        end
      rescue RSolr::Error::Http, CollectionsCreatedError => e
        raise e
      rescue StandardError => e
        status_info(e)
      else
        status_info
      ensure
        self.save!
      end
      return @item
    end

    def add_user_to_permission_templates!
      permission_template = Hyrax::PermissionTemplate.find_or_create_by!(source_id: @item.id)

      Hyrax::PermissionTemplateAccess.find_or_create_by!(
        permission_template_id: permission_template.id,
        agent_id: user.user_key,
        agent_type: 'user',
        access: 'manage'
      )
      Hyrax::PermissionTemplateAccess.find_or_create_by!(
        permission_template_id: permission_template.id,
        agent_id: 'admin',
        agent_type: 'group',
        access: 'manage'
      )

      @item.reset_access_controls!
    end

    def parent_jobs
      self.parsed_metadata[related_parents_parsed_mapping].each do |parent_identifier|
        next if parent_identifier.blank?

        PendingRelationship.create!(child_id: self.identifier, parent_id: parent_identifier, importer_run_id: importerexporter.last_run.id, order: self.id)
      end
    end

    def child_jobs
      self.parsed_metadata[related_children_parsed_mapping].each do |child_identifier|
        next if child_identifier.blank?

        PendingRelationship.create!(parent_id: self.identifier, child_id: child_identifier, importer_run_id: importerexporter.last_run.id, order: self.id)
      end
    end

    def find_collection_ids
      self.collection_ids
    end

    # override this in a sub-class of Entry to ensure any collections have been created before building the work
    def collections_created?
      true
    end

    def build_metadata
      raise StandardError, 'Not Implemented'
    end

    def rights_statement
      parser.parser_fields['rights_statement']
    end

    # try and deal with a couple possible states for this input field
    def override_rights_statement
      %w[true 1].include?(parser.parser_fields['override_rights_statement'].to_s)
    end

    def add_rights_statement
      self.parsed_metadata['rights_statement'] = [parser.parser_fields['rights_statement']] if override_rights_statement || self.parsed_metadata['rights_statement'].blank?
    end

    def add_visibility
      self.parsed_metadata['visibility'] = importerexporter.visibility if self.parsed_metadata['visibility'].blank?
    end

    def add_admin_set_id
      self.parsed_metadata['admin_set_id'] = importerexporter.admin_set_id if self.parsed_metadata['admin_set_id'].blank?
    end

    def add_collections
      return if find_collection_ids.blank?

      self.parsed_metadata['member_of_collections_attributes'] = {}
      find_collection_ids.each_with_index do |c, i|
        self.parsed_metadata['member_of_collections_attributes'][i.to_s] = { id: c }
      end
    end

    # Attempt to sanitize Questioning Authority URI values for configured controlled fields of common
    # data entry mistakes. Controlled URI values are only valid if they are an exact match.
    # Example:
    #   Valid value:     http://rightsstatements.org/vocab/InC/1.0/
    #   Provided value:  https://rightsstatements.org/vocab/InC/1.0
    #   Sanitized value: http://rightsstatements.org/vocab/InC/1.0/ ("s" from "https" removed, trailing "/" added)
    #
    # @return [Boolean] true if all controlled URI values are sanitized successfully
    def sanitize_controlled_uri_values!
      Bulkrax.qa_controlled_properties.each do |field|
        next if parsed_metadata[field].blank?

        parsed_metadata[field].each_with_index do |value, i|
          next if value.blank?

          if (validated_uri_value = validate_value(value, field))
            parsed_metadata[field][i] = validated_uri_value
          else
            debug_msg = %(Unable to locate active authority ID "#{value}" in config/authorities/#{field.pluralize}.yml)
            Rails.logger.debug(debug_msg)
            error_msg = %("#{value}" is not a valid and/or active authority ID for the :#{field} field)
            raise ::StandardError, error_msg
          end
        end
      end

      true
    end

    # @param value [String] value to validate
    # @param field [String] name of the controlled property
    # @return [String, nil] validated URI value or nil
    def validate_value(value, field)
      if value.match?(::URI::DEFAULT_PARSER.make_regexp)
        value = value.strip.chomp
        # add trailing forward slash unless one is already present
        value << '/' unless value.match?(%r{/$})
      end

      valid = if active_id_for_authority?(value, field)
                true
              else
                value.include?('https') ? value.sub!('https', 'http') : value.sub!('http', 'https')
                active_id_for_authority?(value, field)
              end

      valid ? value : nil
    end

    # @param value [String] value to check
    # @param field [String] name of the controlled property
    # @return [Boolean] provided value is a present, active authority ID for the provided field
    def active_id_for_authority?(value, field)
      field_service = ('Hyrax::' + "#{field}_service".camelcase).constantize
      active_authority_ids = field_service.new.active_elements.map { |ae| ae['id'] }

      active_authority_ids.include?(value)
    end

    def factory
      @factory ||= Bulkrax::ObjectFactory.new(attributes: self.parsed_metadata,
                                              source_identifier_value: identifier,
                                              work_identifier: parser.work_identifier,
                                              related_parents_parsed_mapping: parser.related_parents_parsed_mapping,
                                              replace_files: replace_files,
                                              user: user,
                                              klass: factory_class,
                                              importer_run_id: importerexporter.last_run.id,
                                              update_files: update_files)
    end

    def factory_class
      fc = if self.parsed_metadata&.[]('model').present?
             self.parsed_metadata&.[]('model').is_a?(Array) ? self.parsed_metadata&.[]('model')&.first : self.parsed_metadata&.[]('model')
           elsif self.mapping&.[]('work_type').present?
             self.parsed_metadata&.[]('work_type').is_a?(Array) ? self.parsed_metadata&.[]('work_type')&.first : self.parsed_metadata&.[]('work_type')
           else
             Bulkrax.default_work_type
           end

      # return the name of the collection or work
      fc.tr!(' ', '_')
      fc.downcase! if fc.match?(/[-_]/)
      fc.camelcase.constantize
    rescue NameError
      nil
    rescue
      Bulkrax.default_work_type.constantize
    end
  end
end
