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
          add_user_to_permission_templates!
          parent_jobs if self.parsed_metadata[related_parents_parsed_mapping]&.join.present?
          child_jobs if self.parsed_metadata[related_children_parsed_mapping]&.join.present?
        end
      rescue RSolr::Error::Http, CollectionsCreatedError => e
        raise e
      rescue StandardError => e
        set_status_info(e)
      else
        set_status_info
      ensure
        self.save!
      end
      return @item
    end

    def add_user_to_permission_templates!
      # NOTE: This is a cheat for the class is a CollectionEntry.  Consider
      # that we have default_work_type.
      #
      # TODO: This guard clause is not necessary as we can handle it in the
      # underlying factory.  However, to do that requires adjusting about 7
      # failing specs.  So for now this refactor appears acceptable
      return unless defined?(::Hyrax)
      return unless self.class.to_s.include?("Collection")
      factory.add_user_to_collection_permissions(collection: @item, user: user)
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
      return unless defined?(::Hyrax)

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

        if multiple?(field)
          parsed_metadata[field].each_with_index do |value, i|
            next if value.blank?
            parsed_metadata[field][i] = sanitize_controlled_uri_value(field, value)
          end
        else
          parsed_metadata[field] = sanitize_controlled_uri_value(field, parsed_metadata[field])
        end
      end

      true
    end

    def sanitize_controlled_uri_value(field, value)
      if (validated_uri_value = validate_value(value, field))
        validated_uri_value
      else
        debug_msg = %(Unable to locate active authority ID "#{value}" in config/authorities/#{field.pluralize}.yml)
        Rails.logger.debug(debug_msg)
        error_msg = %("#{value}" is not a valid and/or active authority ID for the :#{field} field)
        raise ::StandardError, error_msg
      end
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
      return false unless defined?(::Hyrax)
      field_service = ('Hyrax::' + "#{field}_service".camelcase).constantize
      active_authority_ids = field_service.new.active_elements.map { |ae| ae['id'] }

      active_authority_ids.include?(value)
    end

    def factory
      of = Bulkrax.object_factory || Bulkrax::ObjectFactory
      @factory ||= of.new(attributes: self.parsed_metadata,
                          source_identifier_value: identifier,
                          work_identifier: parser.work_identifier,
                          work_identifier_search_field: parser.work_identifier_search_field,
                          related_parents_parsed_mapping: parser.related_parents_parsed_mapping,
                          replace_files: replace_files,
                          user: user,
                          klass: factory_class,
                          importer_run_id: importerexporter.last_run.id,
                          update_files: update_files)
    end

    def factory_class
      # ATTENTION: Do not memoize this here; tests should catch the problem, but through out the
      # lifecycle of parsing a CSV row or what not, we end up having different factory classes based
      # on the encountered metadata.
      FactoryClassFinder.find(entry: self)
    end
  end
end
