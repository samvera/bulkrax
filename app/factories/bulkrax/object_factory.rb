# frozen_string_literal: true

module Bulkrax
  # rubocop:disable Metrics/ClassLength
  class ObjectFactory < ObjectFactoryInterface
    include Bulkrax::FileFactory

    ##
    # @!group Class Method Interface

    ##
    # @note This does not save either object.  We need to do that in another
    #       loop.  Why?  Because we might be adding many items to the parent.
    def self.add_child_to_parent_work(parent:, child:)
      return true if parent.ordered_members.to_a.include?(child_record)

      parent.ordered_members << child
    end

    def self.add_resource_to_collection(collection:, resource:, user:)
      collection.try(:reindex_extent=, Hyrax::Adapters::NestingIndexAdapter::LIMITED_REINDEX) if
        defined?(Hyrax::Adapters::NestingIndexAdapter)
      resource.member_of_collections << collection
      save!(resource: resource, user: user)
    end

    def self.update_index_for_file_sets_of(resource:)
      resource.file_sets.each(&:update_index) if resource.respond_to?(:file_sets)
    end

    ##
    # @see Bulkrax::ObjectFactoryInterface
    def self.export_properties
      # TODO: Consider how this may or may not work for Valkyrie
      properties = Bulkrax.curation_concerns.map { |work| work.properties.keys }.flatten.uniq.sort
      properties.reject { |prop| Bulkrax.reserved_properties.include?(prop) }
    end

    def self.field_multi_value?(field:, model:)
      return false unless field_supported?(field: field, model: model)
      return false unless model.singleton_methods.include?(:properties)

      model&.properties&.[](field)&.[]("multiple")
    end

    def self.field_supported?(field:, model:)
      model.method_defined?(field) && model.properties[field].present?
    end

    def self.file_sets_for(resource:)
      return [] if resource.blank?
      return [resource] if resource.is_a?(Bulkrax.file_model_class)

      resource.file_sets
    end

    ##
    #
    # @see Bulkrax::ObjectFactoryInterface
    def self.find(id)
      ActiveFedora::Base.find(id)
    rescue ActiveFedora::ObjectNotFoundError => e
      raise ObjectFactoryInterface::ObjectNotFoundError, e.message
    end

    def self.find_or_create_default_admin_set
      # NOTE: Hyrax 5+ removed this method
      AdminSet.find_or_create_default_admin_set_id
    end

    def self.publish(**)
      return true
    end

    ##
    # @param value [String]
    # @param klass [Class, #where]
    # @param field [String, Symbol] A convenience parameter where we pass the
    #        same value to search_field and name_field.
    # @param search_field [String, Symbol] the Solr field name
    #        (e.g. "title_tesim")
    # @param name_field [String] the ActiveFedora::Base property name
    #        (e.g. "title")
    # @param verify_property [TrueClass] when true, verify that the given :klass
    #
    # @return [NilClass] when no object is found.
    # @return [ActiveFedora::Base] when a match is found, an instance of given
    #         :klass
    # rubocop:disable Metrics/ParameterLists
    #
    # @note HEY WE'RE USING THIS FOR A WINGS CUSTOM QUERY.  BE CAREFUL WITH
    #       REMOVING IT.
    #
    # @see # {Wings::CustomQueries::FindBySourceIdentifier#find_by_model_and_property_value}
    def self.search_by_property(value:, klass:, field: nil, search_field: nil, name_field: nil, verify_property: false)
      return nil unless klass.respond_to?(:where)
      # We're not going to try to match nil nor "".
      return if value.blank?
      return if verify_property && !klass.properties.keys.include?(search_field)

      search_field ||= field
      name_field ||= field
      raise "You must provide either (search_field AND name_field) OR field parameters" if search_field.nil? || name_field.nil?
      # NOTE: Query can return partial matches (something6 matches both
      # something6 and something68) so we need to weed out any that are not the
      # correct full match. But other items might be in the multivalued field,
      # so we have to go through them one at a time.
      #
      # A ssi field is string, so we're looking at exact matches.
      # A tesi field is text, so partial matches work.
      #
      # We need to wrap the result in an Array, else we might have a scalar that
      # will result again in partial matches.
      match = klass.where(search_field => value).detect do |m|
        # Don't use Array.wrap as we likely have an ActiveTriples::Relation
        # which defiantly claims to be an Array yet does not behave consistently
        # with an Array.  Hopefully the name_field is not a Date or Time object,
        # Because that too will be a mess.
        Array(m.send(name_field)).include?(value)
      end
      return match if match
    end
    # rubocop:enable Metrics/ParameterLists

    def self.query(q, **kwargs)
      ActiveFedora::SolrService.query(q, **kwargs)
    end

    def self.clean!
      super do
        ActiveFedora::Cleaner.clean!
      end
    end

    def self.solr_name(field_name)
      if defined?(Hyrax)
        Hyrax.index_field_mapper.solr_name(field_name)
      else
        ActiveFedora.index_field_mapper.solr_name(field_name)
      end
    end

    def self.ordered_file_sets_for(object)
      object&.ordered_members.to_a.select(&:file_set?)
    end

    def self.save!(resource:, **)
      resource.save!
    end

    def self.update_index(resources: [])
      Array(resources).each(&:update_index)
    end
    # @!endgroup Class Method Interface
    ##

    def find_by_id
      return false if attributes[:id].blank?
      # Rails / Ruby upgrade, we moved from :exists? to :exist?  However we want to continue (for a
      # bit) to support older versions.
      method_name = klass.respond_to?(:exist?) ? :exist? : :exists?
      klass.find(attributes[:id]) if klass.send(method_name, attributes[:id])
    rescue Valkyrie::Persistence::ObjectNotFoundError
      false
    end

    def delete(_user)
      find&.delete
    end

    private

    # @param [Hash] attrs the attributes to put in the environment
    # @return [Hyrax::Actors::Environment]
    def environment(attrs)
      Hyrax::Actors::Environment.new(object, Ability.new(@user), attrs)
    end

    def work_actor
      Hyrax::CurationConcern.actor
    end

    def create_work(attrs)
      work_actor.create(environment(attrs))
    end

    def update_work(attrs)
      work_actor.update(environment(attrs))
    end

    def create_collection(attrs)
      attrs = clean_attrs(attrs)
      attrs = collection_type(attrs)
      object.attributes = attrs
      object.save!
    end

    def update_collection(attrs)
      object.attributes = attrs
      object.save!
    end

    # This method is heavily inspired by Hyrax's AttachFilesToWorkJob
    def create_file_set(attrs)
      _, work = find_record(attributes[related_parents_parsed_mapping].first, importer_run_id)
      work_permissions = work.permissions.map(&:to_hash)
      attrs = clean_attrs(attrs)
      file_set_attrs = attrs.slice(*object.attributes.keys)
      object.assign_attributes(file_set_attrs)

      attrs['uploaded_files']&.each do |uploaded_file_id|
        uploaded_file = ::Hyrax::UploadedFile.find(uploaded_file_id)
        next if uploaded_file.file_set_uri.present?

        create_file_set_actor(attrs, work, work_permissions, uploaded_file)
      end
      attrs['remote_files']&.each do |remote_file|
        create_file_set_actor(attrs, work, work_permissions, nil, remote_file)
      end

      object.save!
    end

    def create_file_set_actor(attrs, work, work_permissions, uploaded_file, remote_file = nil)
      actor = ::Hyrax::Actors::FileSetActor.new(object, @user)
      uploaded_file&.update(file_set_uri: actor.file_set.uri)
      actor.file_set.permissions_attributes = work_permissions
      actor.create_metadata(attrs)
      actor.create_content(uploaded_file) if uploaded_file
      actor.attach_to_work(work, attrs)
      handle_remote_file(remote_file: remote_file, actor: actor, update: false) if remote_file
    end

    def update_file_set(attrs)
      file_set_attrs = attrs.slice(*object.attributes.keys)
      actor = ::Hyrax::Actors::FileSetActor.new(object, @user)
      attrs['remote_files']&.each do |remote_file|
        handle_remote_file(remote_file: remote_file, actor: actor, update: true)
      end
      actor.update_metadata(file_set_attrs)
    end

    def handle_remote_file(remote_file:, actor:, update: false)
      actor.file_set.label = remote_file['file_name']
      actor.file_set.import_url = remote_file['url']

      url = remote_file['url']
      tmp_file = Tempfile.new(remote_file['file_name'].split('.').first)
      tmp_file.binmode

      URI.open(url) do |url_file|
        tmp_file.write(url_file.read)
      end

      tmp_file.rewind
      update == true ? actor.update_content(tmp_file) : actor.create_content(tmp_file, from_url: true)
      tmp_file.close
    end
  end
  # rubocop:enable Metrics/ClassLength
end
